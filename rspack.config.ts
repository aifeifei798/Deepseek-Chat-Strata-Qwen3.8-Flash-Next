import { readFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { defineConfig } from '@rspack/cli'
import { rspack, type Configuration } from '@rspack/core'

const dev = process.env.NODE_ENV !== 'production'
const targets = ['chrome >= 105', 'edge >= 105', 'safari >= 16', 'firefox >= 110']
const root = path.dirname(fileURLToPath(import.meta.url))
const { version } = JSON.parse(
  readFileSync(new URL('./package.json', import.meta.url), 'utf8')
) as { version: string }

const cssLoader = {
  loader: 'builtin:lightningcss-loader',
  options: { targets },
}

/** 读取仓库根目录的 .env（KEY=VALUE，# 注释，值可带引号）；没有 .env 时返回空对象。 */
const loadEnvFile = (): Record<string, string> => {
  const out: Record<string, string> = {}
  try {
    for (const line of readFileSync(new URL('./.env', import.meta.url), 'utf8').split('\n')) {
      if (line.trim().startsWith('#')) {
        continue
      }
      const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/)
      if (m) {
        out[m[1]] = m[2].replace(/^["']|["']$/g, '')
      }
    }
  } catch {
    // 没有 .env：全部走默认值
  }
  return out
}
// 环境变量优先于 .env 文件
const env = { ...loadEnvFile(), ...process.env } as Record<string, string>

/** Strata 服务地址，开发代理与 serve.sh 共用（见 .env.example） */
const strataUrl = (env.STRATA_URL ?? 'http://127.0.0.1:8080').replace(/\/+$/, '')
/** 开发服务器端口 */
const devPort = Number(env.DEV_PORT ?? 8091)

type ConfigOptions = {
  /** 公开 API 的地址，注入为 __API_ORIGIN__ */
  apiOrigin?: string
  /** 开发服务器配置，支持本地接口代理 */
  devServer?: Configuration['devServer']
}

/** 创建构建配置，支持自定义 API 地址和开发服务器选项 */
export const createConfig = ({
  apiOrigin = 'https://api.deepseek.com',
  devServer,
}: ConfigOptions = {}): Configuration => ({
  mode: dev ? 'development' : 'production',
  entry: './src/main.tsx',
  output: {
    path: path.resolve(root, 'dist'),
    // 运行时按当前脚本地址推导资源路径，file:// 下异步 chunk、字体都按相对位置加载
    publicPath: 'auto',
    filename: 'static/js/[name].[contenthash:8].js',
    chunkFilename: 'static/js/async/[name].[contenthash:8].js',
    cssFilename: 'static/css/[name].[contenthash:8].css',
    cssChunkFilename: 'static/css/async/[name].[contenthash:8].css',
    assetModuleFilename: 'static/media/[name].[contenthash:8][ext]',
    clean: true,
  },
  devtool: dev ? 'cheap-module-source-map' : false,
  // 开发模式预编译异步模块，保持首次加载代码高亮和公式时的页面状态
  lazyCompilation: false,
  resolve: {
    extensions: ['.tsx', '.ts', '.js'],
    // 将 .js 导入路径解析到同名 .ts、.tsx 或 .js 文件
    extensionAlias: { '.js': ['.ts', '.tsx', '.js'] },
  },
  module: {
    // CSS Modules 使用默认导出：`import styles from './x.module.css'`
    parser: { 'css/module': { namedExports: false } },
    generator: { 'css/module': { localIdentName: '[local]-[hash:6]' } },
    rules: [
      { test: /\.module\.css$/, type: 'css/module', use: [cssLoader] },
      { test: /\.css$/, exclude: /\.module\.css$/, type: 'css', use: [cssLoader] },
      {
        test: /\.(j|t)sx?$/,
        exclude: /[\\/]node_modules[\\/]/,
        loader: 'builtin:swc-loader',
        options: {
          jsc: {
            parser: { syntax: 'typescript', tsx: true },
            transform: { react: { runtime: 'automatic', development: dev } },
            externalHelpers: true,
          },
          env: { targets },
        },
        type: 'javascript/auto',
      },
      { test: /\.(woff2?|ttf)$/, type: 'asset/resource' },
    ],
  },
  plugins: [
    // 经典 defer 脚本支持 file:// 页面的资源加载
    new rspack.HtmlRspackPlugin({
      template: './src/index.html',
      scriptLoading: 'defer',
      meta: { 'application-version': version },
    }),
    new rspack.DefinePlugin({ __API_ORIGIN__: JSON.stringify(apiOrigin) }),
    new rspack.CopyRspackPlugin({
      patterns: [{ from: path.resolve(root, 'LICENSE'), to: 'LICENSE', toType: 'file' }],
    }),
  ],
  performance: { hints: false },
  devServer: { port: 8090, ...devServer },
})

// 本地接 Strata：API 地址默认留空走同源，开发服务器把 /anthropic/* 改写到 Strata 的 /v1/*，
// /models 原样转发；Strata 地址与端口从 .env 读取（见 .env.example）。
// 只影响 `pnpm dev`；`pnpm build` 仍指向 https://api.deepseek.com，除非 .env 里显式设置 API_ORIGIN。
// eslint-disable-next-line import/no-default-export
export default defineConfig(
  createConfig({
    apiOrigin: env.API_ORIGIN ?? (dev ? '' : 'https://api.deepseek.com'),
    devServer: {
      port: Number.isFinite(devPort) && devPort > 0 ? devPort : 8091,
      proxy: [
        {
          context: '/anthropic',
          // 请求带 x-strata-url 头（设置里的 Strata 地址）时按头转发，否则用 .env 的 STRATA_URL
          target: strataUrl,
          router: (req) => (req.headers['x-strata-url'] as string | undefined) || strataUrl,
          changeOrigin: true,
          pathRewrite: { '^/anthropic': '' },
        },
        {
          context: '/models',
          target: strataUrl,
          router: (req) => (req.headers['x-strata-url'] as string | undefined) || strataUrl,
          changeOrigin: true,
        },
      ],
    },
  })
)
