/** 品牌 logo：剖面地层的聊天气泡（三条白条 = strata）。气泡用主题品牌色，深浅色自适应。 */
export const BrandMark = ({ size = 22, className }: { size?: number; className?: string }) => (
  <svg
    className={className}
    width={size}
    height={size}
    viewBox="0 0 24 24"
    role="img"
    aria-hidden="true"
    focusable="false"
  >
    <path
      d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2z"
      fill="var(--dsw-alias-brand-primary)"
    />
    <rect x="4.6" y="6" width="14.8" height="2.7" rx="1.35" fill="#fff" opacity=".34" />
    <rect x="4.6" y="10.2" width="14.8" height="2.7" rx="1.35" fill="#fff" opacity=".55" />
    <rect x="4.6" y="14.4" width="14.8" height="2.7" rx="1.35" fill="#fff" opacity=".8" />
  </svg>
)
