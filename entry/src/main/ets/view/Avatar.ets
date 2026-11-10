/**
 * 头像组件：支持三种来源（都在 `store.getAvatar()` 里编码）
 *   ''                 用姓名首字 + 主题色（默认）
 *   'preset:<index>'   内置配色/形状
 *   'file:<uri>'       用户从相册选的图片
 *
 * 之所以做成组件：顶栏（32）、抽屉（40）、账号页（72）三处要用，逻辑只写一份。
 */
import { Theme } from '../common/Theme';
import { store } from '../service/Store';

/** 内置头像：8 种渐变 + 首字，够用且不引入资源文件。 */
export interface AvatarPreset {
  id: string;
  from: string;
  to: string;
  /** 圆形 / 圆角方形 */
  round: boolean;
}

export const AVATAR_PRESETS: AvatarPreset[] = [
  { id: '0', from: '#E8A08A', to: '#C15F3C', round: true },
  { id: '1', from: '#7FB3D5', to: '#2E6DA4', round: true },
  { id: '2', from: '#8FD1A8', to: '#2F855A', round: true },
  { id: '3', from: '#C7B3E8', to: '#6B46C1', round: true },
  { id: '4', from: '#F0C36D', to: '#B7791F', round: true },
  { id: '5', from: '#9AA5B1', to: '#3E4C59', round: false },
  { id: '6', from: '#F29CB7', to: '#B83280', round: false },
  { id: '7', from: '#7DD3C0', to: '#0F766E', round: false }
];

export function findPreset(id: string): AvatarPreset {
  for (let i = 0; i < AVATAR_PRESETS.length; i++) {
    if (AVATAR_PRESETS[i].id === id) {
      return AVATAR_PRESETS[i];
    }
  }
  return AVATAR_PRESETS[0];
}

@Component
export struct Avatar {
  @Prop avatarSize: number = 32;
  @Prop fontSize: number = 13;
  @Prop name: string = '';
  @Prop avatar: string = '';
  onTap: () => void = () => {
  };

  private initial(): string {
    return this.name.length > 0 ? this.name.substring(0, 1) : '我';
  }

  build() {
    Stack() {
      if (this.avatar.startsWith('file:')) {
        Image(this.avatar.substring(5))
          .width(this.avatarSize)
          .height(this.avatarSize)
          .borderRadius(this.avatarSize / 2)
          .objectFit(ImageFit.Cover)
          .backgroundColor(Theme.surfaceAlt)
      } else if (this.avatar.startsWith('preset:')) {
        Column() {
          Text(this.initial())
            .fontSize(this.fontSize)
            .fontColor('#FFFFFF')
            .fontWeight(FontWeight.Medium)
        }
        .width(this.avatarSize)
        .height(this.avatarSize)
        .justifyContent(FlexAlign.Center)
        .linearGradient({
          angle: 135,
          colors: [[findPreset(this.avatar.substring(7)).from, 0.0],
            [findPreset(this.avatar.substring(7)).to, 1.0]]
        })
        .borderRadius(findPreset(this.avatar.substring(7)).round ? this.avatarSize / 2 : this.avatarSize / 4)
      } else {
        Text(this.initial())
          .fontSize(this.fontSize)
          .fontColor(Theme.textOnAccent)
          .width(this.avatarSize)
          .height(this.avatarSize)
          .textAlign(TextAlign.Center)
          .borderRadius(this.avatarSize / 2)
          .backgroundColor(Theme.accent)
      }
    }
    .width(this.avatarSize)
    .height(this.avatarSize)
    .onClick(() => {
      this.onTap();
    })
  }
}

/** 当前头像值（组件用 @Prop 传值，避免各页面直接读 store 造成不刷新）。 */
export function currentAvatar(): string {
  return store.getAvatar();
}
