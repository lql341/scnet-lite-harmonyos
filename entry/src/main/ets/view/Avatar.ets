/**
 * 头像组件与预设。
 *
 * 三种来源（都编码在 `store.getAvatar()`）：
 *   ''                默认：姓名首字 + 主题色
 *   'preset:<index>'  预设（下面 AVATAR_PRESETS，三种风格：卡通 / 风景 / 字母）
 *   'file:<uri>'      用户从相册选的图片
 *
 * ⚠️ 踩坑：不要在 Avatar 根节点上无条件挂 onClick —— 它会吃掉外层的手势，
 * 导致「头像选择面板里点不动」。这里只有传了 onTap 才挂。
 */
import { Theme } from '../common/Theme';

/** 'cartoon' 表情卡通 / 'scene' 风景 / 'mono' 字母（默认配色） */
export type AvatarStyle = 'cartoon' | 'scene' | 'mono';

export interface AvatarPreset {
  id: string;
  style: AvatarStyle;
  /** cartoon: emoji；mono: 空（用姓名首字） */
  glyph: string;
  from: string;
  to: string;
  /** 圆形 / 圆角方形 */
  round: boolean;
  label: string;
}

export const AVATAR_PRESETS: AvatarPreset[] = [
  // 卡通 / 表情
  { id: '0', style: 'cartoon', glyph: '🐼', from: '#F7EDE6', to: '#E3C3B0', round: true, label: '熊猫' },
  { id: '1', style: 'cartoon', glyph: '🦊', from: '#FFE7D3', to: '#F0A97B', round: true, label: '狐狸' },
  { id: '2', style: 'cartoon', glyph: '🐳', from: '#DCEEF8', to: '#8FBEDC', round: true, label: '鲸鱼' },
  { id: '3', style: 'cartoon', glyph: '🦉', from: '#EDE7F6', to: '#B7A6D9', round: true, label: '猫头鹰' },
  { id: '4', style: 'cartoon', glyph: '🐙', from: '#FBE3E8', to: '#E0A0B2', round: true, label: '章鱼' },
  { id: '5', style: 'cartoon', glyph: '🌵', from: '#E4F2E4', to: '#9CC79C', round: true, label: '仙人掌' },
  // 风景
  { id: '6', style: 'scene', glyph: 'sun', from: '#FDE7C8', to: '#E8A87C', round: true, label: '日落' },
  { id: '7', style: 'scene', glyph: 'wave', from: '#DCEBF6', to: '#7FA8C4', round: true, label: '海面' },
  { id: '8', style: 'scene', glyph: 'mountain', from: '#E7EDF3', to: '#94A3B1', round: false, label: '雪山' },
  { id: '9', style: 'scene', glyph: 'night', from: '#22304A', to: '#0E1A2B', round: true, label: '星空' },
  // 字母（默认配色）
  { id: '10', style: 'mono', glyph: '', from: '#E8A08A', to: '#C15F3C', round: true, label: '陶土' },
  { id: '11', style: 'mono', glyph: '', from: '#9AA5B1', to: '#3E4C59', round: false, label: '石墨' }
];

/** 面板里的分组顺序 */
export const AVATAR_GROUPS: string[] = ['卡通', '风景', '字母'];

export function presetsOf(style: AvatarStyle): AvatarPreset[] {
  const out: AvatarPreset[] = [];
  for (let i = 0; i < AVATAR_PRESETS.length; i++) {
    if (AVATAR_PRESETS[i].style === style) {
      out.push(AVATAR_PRESETS[i]);
    }
  }
  return out;
}

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
  /** 只有传了回调才挂点击，避免吃掉外层的点击 */
  onTap?: () => void;

  private initial(): string {
    return this.name.length > 0 ? this.name.substring(0, 1) : '我';
  }

  /** 风景类用简单图形拼（不引资源文件）。 */
  @Builder
  scene(preset: AvatarPreset) {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [[preset.from, 0.0], [preset.to, 1.0]]
        })
      if (preset.glyph === 'sun') {
        Column()
          .width(this.avatarSize * 0.42)
          .height(this.avatarSize * 0.42)
          .borderRadius(this.avatarSize)
          .backgroundColor('#FFF3D6')
          .offset({ y: -this.avatarSize * 0.16 })
      } else if (preset.glyph === 'wave') {
        Column()
          .width('120%')
          .height(this.avatarSize * 0.42)
          .borderRadius(this.avatarSize)
          .backgroundColor('#FFFFFF88')
          .offset({ y: this.avatarSize * 0.18 })
      } else if (preset.glyph === 'mountain') {
        Column()
          .width(this.avatarSize * 0.9)
          .height(this.avatarSize * 0.9)
          .backgroundColor('#FFFFFFAA')
          .rotate({ angle: 45 })
          .offset({ y: this.avatarSize * 0.30 })
      } else if (preset.glyph === 'night') {
        Column()
          .width(this.avatarSize * 0.16)
          .height(this.avatarSize * 0.16)
          .borderRadius(this.avatarSize)
          .backgroundColor('#FFFFFF')
          .offset({ x: -this.avatarSize * 0.2, y: -this.avatarSize * 0.2 })
        Column()
          .width(this.avatarSize * 0.1)
          .height(this.avatarSize * 0.1)
          .borderRadius(this.avatarSize)
          .backgroundColor('#FFFFFFAA')
          .offset({ x: this.avatarSize * 0.18, y: this.avatarSize * 0.12 })
      }
    }
    .width(this.avatarSize)
    .height(this.avatarSize)
    .clip(true)
    .borderRadius(preset.round ? this.avatarSize / 2 : this.avatarSize / 4)
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
        if (findPreset(this.avatar.substring(7)).style === 'scene') {
          this.scene(findPreset(this.avatar.substring(7)))
        } else {
          Column() {
            Text(findPreset(this.avatar.substring(7)).style === 'cartoon'
              ? findPreset(this.avatar.substring(7)).glyph
              : this.initial())
              .fontSize(findPreset(this.avatar.substring(7)).style === 'cartoon'
                ? this.avatarSize * 0.52 : this.fontSize)
              .fontColor(findPreset(this.avatar.substring(7)).style === 'cartoon'
                ? '#1F1E1D' : '#FFFFFF')
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
        }
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
      // 统一在这里处理点击：调用方只需传 onTap，不必再套外层 onClick
      const handler: (() => void) | undefined = this.onTap;
      if (handler !== undefined) {
        handler();
      }
    })
  }
}
