package cn.scnet.agent.svc;

import org.json.JSONArray;
import org.json.JSONObject;

import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import cn.scnet.agent.core.Hmac;
import cn.scnet.agent.core.Http;
import cn.scnet.agent.core.J;
import cn.scnet.agent.core.Store;

/**
 * SCNet HPC OpenAPI 客户端（AK/SK 签名，对齐 ArkTS 的 service/Hpc.ets）。
 *
 * 链路：
 *   POST api.scnet.cn/api/user/v3/tokens（user/accessKey/signature/timestamp）
 *     → [{clusterId, clusterName, token}]（每集群一个 JWT，TTL 4h）
 *   GET  www.scnet.cn/ac/openapi/v2/center   → hpcUrls / efileUrls / homePath
 *   GET  {hpc}/hpc/openapi/v2/cluster        → 调度器 id
 *   GET  .../queuenames/users/{user}、.../userquotas/userlimit、.../jobs
 *   POST .../apptemplates/BASIC/BASE/job     → 提交（真计费！默认 dry-run）
 *   DELETE .../jobs?jobMethod=5&strJobInfoMap=…
 */
public class Hpc {

    private static final String API_BASE_DEFAULT = "https://api.scnet.cn";
    private static final String WEB_BASE_DEFAULT = "https://www.scnet.cn";

    /** 联调用：debugApiBase 非空时把 HPC 域名也指向 mock。 */
    private static String apiBase() {
        try {
            String override = Store.get().getDebugBase();
            if (override != null && override.trim().length() > 0) {
                return J.trimSlash(override.trim());
            }
        } catch (Exception ignored) {
        }
        return API_BASE_DEFAULT;
    }

    private static String webBase() {
        return apiBase();
    }

    public static class Region {
        public String clusterId = "";
        public String clusterName = "";
        public String token = "";
    }

    public static class Queue {
        public String name = "";
        public String freeCpus = "";
        public String totalCpus = "";
        public String maxPpn = "";
        public String nodes = "";
    }

    public static class Quota {
        public String userName = "";
        public int accountMaxCpu;
        public int accountMaxDcu;
        public int accountMaxJob;
        public int accountMaxRun;
    }

    public static class Entry {
        public String name = "";
        public String path = "";
    }

    public static class Context {
        public String clusterId = "";
        public String clusterName = "";
        public String token = "";
        public String hpcUrl = "";
        public String efileUrl = "";
        public String userName = "";
        public String homePath = "";
        public String schedulerId = "";
    }

    /** 提交计划（表单 + sbatch 预览的共同数据源）。 */
    public static class Plan {
        public String name = "";
        public String queue = "";
        public int nodes = 1;
        /** 每节点核数 */
        public int cpus = 1;
        public int gpus;
        public int dcus;
        public String memory = "";
        public String walltime = "00:30:00";
        public String workDir = "";
        public String command = "";
        public boolean exclusive;
        public boolean allowSubmit;
    }

    public static class HpcError extends Exception {
        public final String code;

        public HpcError(String code, String message) {
            super(message);
            this.code = code;
        }
    }

    private static final Hpc INSTANCE = new Hpc();

    private List<Region> regionCache = new ArrayList<>();
    private long regionsAt;
    private final Map<String, Context> contexts = new HashMap<>();

    public static Hpc get() {
        return INSTANCE;
    }

    public boolean hasCredentials() {
        return Store.get().getHpcAk().length() > 0 && Store.get().getHpcSk().length() > 0;
    }

    /** AK/SK 都是 32 位十六进制（重复粘贴会变 64 位，直接拒掉比签名失败好排查）。 */
    public String validateCreds(String ak, String sk) {
        if (!ak.matches("^[0-9a-fA-F]{32}$")) {
            return "AccessKey 应为 32 位十六进制";
        }
        if (!sk.matches("^[0-9a-fA-F]{32}$")) {
            return "SecretKey 应为 32 位十六进制";
        }
        return "";
    }

    /** 渲染等价 sbatch（给人复核）。 */
    public static String renderSbatch(Plan plan, String stdout, String stderr) {
        StringBuilder sb = new StringBuilder();
        sb.append("#!/bin/bash\n");
        sb.append("#SBATCH --job-name=").append(plan.name).append('\n');
        sb.append("#SBATCH --partition=").append(plan.queue).append('\n');
        sb.append("#SBATCH --nodes=").append(plan.nodes).append('\n');
        sb.append("#SBATCH --ntasks-per-node=").append(plan.cpus).append('\n');
        if (plan.gpus > 0) {
            sb.append("#SBATCH --gres=gpu:").append(plan.gpus).append('\n');
        }
        if (plan.dcus > 0) {
            sb.append("#SBATCH --gres=dcu:").append(plan.dcus).append('\n');
        }
        if (plan.memory.length() > 0) {
            sb.append("#SBATCH --mem=").append(plan.memory).append('\n');
        }
        sb.append("#SBATCH --time=").append(plan.walltime).append('\n');
        sb.append("#SBATCH --chdir=").append(plan.workDir).append('\n');
        sb.append("#SBATCH --output=").append(stdout).append('\n');
        sb.append("#SBATCH --error=").append(stderr).append('\n');
        if (plan.exclusive) {
            sb.append("#SBATCH --exclusive\n");
        }
        sb.append("\nset -euo pipefail\n").append(plan.command).append('\n');
        return sb.toString();
    }

    /** 表单校验：空串 = 通过。 */
    public static String validate(Plan plan, List<String> queues) {
        if (plan.name.trim().length() == 0) {
            return "作业名不能为空";
        }
        if (plan.queue.length() == 0) {
            return "请选择队列";
        }
        if (!queues.isEmpty() && !queues.contains(plan.queue)) {
            return "队列 " + plan.queue + " 不在可用列表里";
        }
        if (plan.nodes < 1 || plan.nodes > 64) {
            return "节点数应在 1~64";
        }
        if (plan.cpus < 1 || plan.cpus > 64) {
            return "每节点核数应在 1~64";
        }
        if (!plan.walltime.matches("^\\d{2}:\\d{2}:\\d{2}$")) {
            return "运行时长格式应为 HH:MM:SS";
        }
        if (plan.workDir.length() == 0 || !plan.workDir.startsWith("/")) {
            return "工作目录必须是绝对路径";
        }
        if (plan.command.trim().length() == 0) {
            return "命令不能为空";
        }
        return "";
    }

    /** AK/SK → 各集群 token（缓存 3.5 小时）。 */
    public List<Region> regions(boolean refresh) throws HpcError {
        if (!refresh && !regionCache.isEmpty()
                && System.currentTimeMillis() - regionsAt < 3.5 * 3600 * 1000) {
            return regionCache;
        }
        String ak = Store.get().getHpcAk();
        String sk = Store.get().getHpcSk();
        String user = Store.get().getHpcUser();
        if (user.length() == 0) {
            user = Store.get().getPlatformUserName();
        }
        if (ak.length() == 0 || sk.length() == 0) {
            throw new HpcError("no-creds", "未配置 AK/SK");
        }
        String ts = String.valueOf(System.currentTimeMillis() / 1000);
        String message = Hmac.hpcSignMessage(ak, ts, user);
        String signature = Hmac.hmacHex(sk, message);

        Map<String, String> head = new LinkedHashMap<>();
        head.put("user", user);
        head.put("accessKey", ak);
        head.put("signature", signature);
        head.put("timestamp", ts);
        try {
            Http.Response resp = Http.send("POST", apiBase() + "/api/user/v3/tokens", head, null);
            if (resp.status != 200) {
                throw new HpcError(String.valueOf(resp.status),
                        "签名/凭据被拒：" + cut(resp.body, 120));
            }
            Object parsed = resp.body.trim().startsWith("[")
                    ? new JSONArray(resp.body) : new JSONObject(resp.body);
            JSONArray list;
            if (parsed instanceof JSONArray) {
                list = (JSONArray) parsed;
            } else {
                JSONObject env = (JSONObject) parsed;
                Object data = env.opt("data");
                list = data instanceof JSONArray ? (JSONArray) data : new JSONArray();
            }
            List<Region> out = new ArrayList<>();
            for (int i = 0; i < list.length(); i++) {
                JSONObject row = J.at(list, i);
                Region r = new Region();
                r.clusterId = J.str(row, "clusterId");
                r.clusterName = J.str(row, "clusterName");
                r.token = J.str(row, "token");
                if (r.token.length() > 0) {
                    out.add(r);
                }
            }
            regionCache = out;
            regionsAt = System.currentTimeMillis();
            return out;
        } catch (HpcError e) {
            throw e;
        } catch (Exception e) {
            throw new HpcError("network", e.getMessage() == null ? "获取集群令牌失败" : e.getMessage());
        }
    }

    private JSONObject getJson(String url, String token) throws Exception {
        Map<String, String> head = new LinkedHashMap<>();
        head.put("token", token);
        head.put("Content-Type", "application/json");
        head.put("Accept", "application/json");
        Http.Response resp = Http.send("GET", url, head, null);
        return J.obj(resp.body);
    }

    /** 区域中心（hpc/efile 域名、home、用户名）+ 调度器 id。 */
    public Context context(String clusterId, boolean refresh) throws HpcError {
        // 还没选过集群（"0" / 空）时用第一个可用区域，别让入口直接报错
        if (clusterId == null || clusterId.length() == 0 || "0".equals(clusterId)) {
            List<Region> all = regions(refresh);
            for (Region r : all) {
                if (!"0".equals(r.clusterId)) {
                    clusterId = r.clusterId;
                    break;
                }
            }
        }
        if (!refresh) {
            Context cached = contexts.get(clusterId);
            if (cached != null) {
                return cached;
            }
        }
        List<Region> regions = regions(refresh);
        Region picked = null;
        for (Region r : regions) {
            if (r.clusterId.equals(clusterId)) {
                picked = r;
                break;
            }
        }
        if (picked == null) {
            throw new HpcError("no-region", "集群 " + clusterId + " 没有可用令牌");
        }
        try {
            JSONObject centerEnv = getJson(webBase() + "/ac/openapi/v2/center", picked.token);
            JSONObject center = J.jo(centerEnv, "data");
            JSONArray hpcUrls = J.ja(center, "hpcUrls");
            JSONArray efileUrls = J.ja(center, "efileUrls");
            JSONObject clusterUser = J.jo(center, "clusterUserInfo");
            String hpcUrl = "";
            for (int i = 0; i < hpcUrls.length(); i++) {
                JSONObject row = J.at(hpcUrls, i);
                if ("true".equals(J.str(row, "enable"))) {
                    hpcUrl = J.str(row, "url");
                    break;
                }
            }
            String efileUrl = efileUrls.length() > 0 ? J.str(J.at(efileUrls, 0), "url") : "";
            if (hpcUrl.length() == 0) {
                throw new HpcError("no-hpc", "区域中心没有返回 hpc 地址");
            }
            JSONObject schedulerEnv = getJson(hpcUrl + "/hpc/openapi/v2/cluster", picked.token);
            JSONArray schedulers = J.ja(schedulerEnv, "data");
            String schedulerId = schedulers.length() > 0
                    ? J.str(J.at(schedulers, 0), "id") : "";
            Context ctx = new Context();
            ctx.clusterId = picked.clusterId;
            ctx.clusterName = picked.clusterName;
            ctx.token = picked.token;
            ctx.hpcUrl = hpcUrl;
            ctx.efileUrl = efileUrl;
            ctx.userName = J.str(clusterUser, "userName");
            ctx.homePath = J.str(clusterUser, "homePath");
            ctx.schedulerId = schedulerId;
            contexts.put(clusterId, ctx);
            return ctx;
        } catch (HpcError e) {
            throw e;
        } catch (Exception e) {
            throw new HpcError("network", e.getMessage() == null ? "获取区域中心失败" : e.getMessage());
        }
    }

    public List<Queue> queues(Context ctx) throws Exception {
        String url = ctx.hpcUrl + "/hpc/openapi/v2/queuenames/users/"
                + Http.enc(ctx.userName) + "?strJobManagerID=" + Http.enc(ctx.schedulerId);
        JSONObject env = getJson(url, ctx.token);
        JSONArray rows = J.ja(env, "data");
        List<Queue> out = new ArrayList<>();
        for (int i = 0; i < rows.length(); i++) {
            JSONObject row = J.at(rows, i);
            Queue q = new Queue();
            q.name = J.str(row, "queueName");
            if (q.name.length() == 0) {
                q.name = J.str(row, "name");
            }
            q.freeCpus = J.str(row, "queFreeNcpus");
            q.totalCpus = J.str(row, "queNcpus");
            q.maxPpn = J.str(row, "queMaxPPN");
            q.nodes = J.str(row, "queNodes");
            if (q.name.length() > 0) {
                out.add(q);
            }
        }
        return out;
    }

    public Quota quota(Context ctx) {
        try {
            String url = ctx.hpcUrl + "/hpc/openapi/v2/userquotas/userlimit"
                    + "?strJobManagerID=" + Http.enc(ctx.schedulerId);
            JSONObject env = getJson(url, ctx.token);
            JSONObject d = J.jo(env, "data");
            Quota q = new Quota();
            q.userName = J.str(d, "userName");
            q.accountMaxCpu = J.i(d, "accountMaxCpu");
            q.accountMaxDcu = J.i(d, "accountMaxDcu");
            q.accountMaxJob = J.i(d, "accountMaxSubmitJob");
            q.accountMaxRun = J.i(d, "accountMaxRunJob");
            return q;
        } catch (Exception e) {
            return null;
        }
    }

    /** 提交体：GAP_NPROC 是**总核数**，GAP_NGPU/NDCU 是**每节点**。 */
    public JSONObject buildSubmitBody(Context ctx, Plan plan, String stdout, String stderr)
            throws Exception {
        JSONObject info = new JSONObject();
        info.put("GAP_CMD_FILE", plan.command);
        info.put("GAP_NNODE", String.valueOf(plan.nodes));
        info.put("GAP_NODE_STRING", "");
        info.put("GAP_SUBMIT_TYPE", "cmd");
        info.put("GAP_JOB_NAME", plan.name);
        info.put("GAP_WORK_DIR", plan.workDir);
        info.put("GAP_QUEUE", plan.queue);
        info.put("GAP_NPROC", String.valueOf(plan.cpus * plan.nodes));
        info.put("GAP_PPN", "");
        info.put("GAP_NGPU", plan.gpus > 0 ? String.valueOf(plan.gpus) : "");
        info.put("GAP_NDCU", plan.dcus > 0 ? String.valueOf(plan.dcus) : "");
        info.put("GAP_JOB_MEM", plan.memory);
        info.put("GAP_WALL_TIME", plan.walltime);
        info.put("GAP_EXCLUSIVE", plan.exclusive ? "1" : "");
        info.put("GAP_APPNAME", "BASE");
        info.put("GAP_MULTI_SUB", "");
        info.put("GAP_STD_OUT_FILE", stdout);
        info.put("GAP_STD_ERR_FILE", stderr);
        info.put("GAP_SCHEDULER_OPT_WEB", "");
        info.put("GAP_CLUSTER_ID", ctx.clusterId);
        JSONObject body = new JSONObject();
        body.put("strJobManagerID", ctx.schedulerId);
        body.put("mapAppJobInfo", info);
        return body;
    }

    /** 真提交（会真计费）。UI 必须二次确认后才允许走到这里。 */
    public String submit(Context ctx, Plan plan, String stdout, String stderr) throws HpcError {
        try {
            JSONObject body = buildSubmitBody(ctx, plan, stdout, stderr);
            Map<String, String> head = new LinkedHashMap<>();
            head.put("token", ctx.token);
            head.put("Content-Type", "application/json");
            head.put("Accept", "application/json");
            Http.Response resp = Http.send("POST",
                    ctx.hpcUrl + "/hpc/openapi/v2/apptemplates/BASIC/BASE/job",
                    head, body.toString().getBytes("UTF-8"));
            JSONObject env = J.obj(resp.body);
            String code = J.str(env, "code");
            if (code.length() > 0 && !"0".equals(code)) {
                throw new HpcError(code, J.str(env, "msg", "提交被拒绝"));
            }
            Object data = env.opt("data");
            String jobId = data == null ? "" : String.valueOf(data).trim();
            if (jobId.length() == 0) {
                throw new HpcError("no-id", "提交成功但没有返回作业号");
            }
            return jobId;
        } catch (HpcError e) {
            throw e;
        } catch (Exception e) {
            throw new HpcError("network", e.getMessage() == null ? "提交失败" : e.getMessage());
        }
    }

    /** 列远程目录（efile；根目录 / 无权限，需从 home 起）。 */
    public List<Entry> listDir(Context ctx, String path) throws Exception {
        String url = ctx.efileUrl + "/openapi/v2/file/list?path=" + Http.enc(path);
        JSONObject env = getJson(url, ctx.token);
        String code = J.str(env, "code");
        if (code.length() > 0 && !"0".equals(code)) {
            throw new HpcError(code, J.str(env, "msg", "读取目录失败"));
        }
        JSONArray children = J.ja(J.jo(env, "data"), "children");
        List<Entry> out = new ArrayList<>();
        for (int i = 0; i < children.length(); i++) {
            JSONObject row = J.at(children, i);
            Entry e = new Entry();
            e.name = J.str(row, "label");
            e.path = J.str(row, "path");
            if (e.name.length() > 0) {
                out.add(e);
            }
        }
        java.util.Collections.sort(out, new java.util.Comparator<Entry>() {
            @Override
            public int compare(Entry a, Entry b) {
                return a.name.compareToIgnoreCase(b.name);
            }
        });
        return out;
    }

    /** 读远程文件（hpc 的 file/content，form 提交）。 */
    public String readFile(Context ctx, String path, boolean tail) throws Exception {
        Map<String, String> head = new LinkedHashMap<>();
        head.put("token", ctx.token);
        head.put("Content-Type", "application/x-www-form-urlencoded");
        String form = "hostName=&dirPath=" + Http.enc(path) + "&triggerNum=1&rollDirection="
                + (tail ? "UP" : "DOWN");
        Http.Response resp = Http.send("POST", ctx.hpcUrl + "/hpc/openapi/v2/file/content",
                head, form.getBytes("UTF-8"));
        JSONObject env = J.obj(resp.body);
        String code = J.str(env, "code");
        if (code.length() > 0 && !"0".equals(code)) {
            throw new HpcError(code, J.str(env, "msg", "读取文件失败"));
        }
        return J.str(J.jo(env, "data"), "data");
    }

    public JSONObject jobDetail(Context ctx, String jobId) {
        try {
            JSONObject env = getJson(ctx.hpcUrl + "/hpc/openapi/v2/jobs/" + Http.enc(jobId), ctx.token);
            JSONObject data = J.jo(env, "data");
            return data.length() == 0 ? null : data;
        } catch (Exception e) {
            return null;
        }
    }

    /** 取消：`strJobInfoMap=<scheduler>,<user>:<jobId>:`，服务端对不存在的 id 也回 0。 */
    public void cancel(Context ctx, String jobId) throws Exception {
        Map<String, String> head = new LinkedHashMap<>();
        head.put("token", ctx.token);
        head.put("Content-Type", "application/x-www-form-urlencoded");
        String map = ctx.schedulerId + "," + ctx.userName + ":" + jobId + ":";
        String form = "jobMethod=5&strJobInfoMap=" + Http.enc(map);
        Http.Response resp = Http.send("DELETE", ctx.hpcUrl + "/hpc/openapi/v2/jobs",
                head, form.getBytes("UTF-8"));
        JSONObject env = J.obj(resp.body);
        String code = J.str(env, "code");
        if (code.length() > 0 && !"0".equals(code)) {
            throw new HpcError(code, J.str(env, "msg", "取消失败"));
        }
    }

    /** 作业列表（平台偶发 10001 internal_error，向上抛由 UI 展示）。 */
    public List<JSONObject> jobs(Context ctx, int limit) throws Exception {
        String url = ctx.hpcUrl + "/hpc/openapi/v2/jobs?strClusterIDList="
                + Http.enc(ctx.schedulerId) + "&start=0&limit=" + limit;
        JSONObject env = getJson(url, ctx.token);
        String code = J.str(env, "code");
        if (code.length() > 0 && !"0".equals(code)) {
            throw new HpcError(code, J.str(env, "msg", "查询作业失败"));
        }
        Object data = env.opt("data");
        JSONArray rows;
        if (data instanceof JSONArray) {
            rows = (JSONArray) data;
        } else {
            rows = J.ja(J.jo(env, "data"), "list");
        }
        List<JSONObject> out = new ArrayList<>();
        for (int i = 0; i < rows.length(); i++) {
            JSONObject row = rows.optJSONObject(i);
            if (row != null) {
                out.add(row);
            }
        }
        return out;
    }

    /** 作业状态中文化 + 着色用。 */
    public static String jobStateText(String state) {
        if (state == null) {
            return "";
        }
        switch (state.toUpperCase()) {
            case "R":
                return "运行中";
            case "PD":
            case "PENDING":
                return "排队中";
            case "CD":
            case "COMPLETED":
                return "已完成";
            case "F":
                return "已结束";
            case "CA":
                return "已取消";
            case "CF":
                return "配置失败";
            case "TO":
            case "TIMEOUT":
                return "超时";
            case "OOM":
                return "内存不足";
            case "NF":
                return "节点故障";
            default:
                return state;
        }
    }

    private static String cut(String text, int max) {
        if (text == null) {
            return "";
        }
        return text.length() > max ? text.substring(0, max) : text;
    }
}
