/**
 * server/lib/blob.ts —— Vercel Blob 就绪判定（/api/health 与 /api/upload 共用）
 *
 * 为什么需要这个模块：Vercel Blob 现在有两种认证模式，只判一种会出「假警报」——
 *   A. OIDC（官方推荐）：项目连上 Blob Store 后，Vercel 自动注入 BLOB_STORE_ID + OIDC 凭证，
 *      **不会**给你BLOB_READ_WRITE_TOKEN。旧代码只认 token → 上传其实成功了，自检却报「未配置」。
 *   B. 长效 token：Store → Tokens → Create Token 手动生成 BLOB_READ_WRITE_TOKEN，
 *      用于代码在 Vercel 之外运行（本地脚本、CI、client upload）。
 *
 * 另外：env 里有变量 ≠ store 真能用。Hobby 各项用量超限时 Vercel 会直接封停 store
 * （list/put 全部 403 "store has been suspended"），代码侧无解只能提工单。
 * 所以就绪与否必须**实测**（list 一条），并把真实原因透出去。
 */
import { list } from '@vercel/blob';

/** 是否检测到任一模式的配置 */
export function blobConfigured(): boolean {
  return Boolean(process.env.BLOB_STORE_ID || process.env.BLOB_READ_WRITE_TOKEN);
}

/**
 *🔒 私密 store（存放身体部位图/私密相册）——与公开 store 分开的第二套凭据
 *
 * 为什么必须分开：Vercel Blob 的 access 属性是 **store 级**的，同一个 store 里
 * 不能一半 public 一半 private。要私密就得单独建一个 access=Private 的 store，
 * Vercel 会给它独立的环境变量前缀（默认 BLOB_，这里约定 PRIVATE_BLOB_）。
 *
 * 配置方式：Vercel → Storage → Create Storage → Blob → access 选 Private
 *          → Advanced Options 把 prefix 设为 PRIVATE_BLOB_ → Connect to Project
 *
 *⚠️ 未配置时私密上传**直接报错**，绝不静默回退到公开 store——
 *    回退意味着私密照片以公开 URL 落盘，等于这次改造没做。
 *    这是刻意的「失败优于裸奔」设计。
 */
export function privateBlobConfigured(): boolean {
  return Boolean(
    process.env.PRIVATE_BLOB_STORE_ID || process.env.PRIVATE_BLOB_READ_WRITE_TOKEN,
  );
}

/** 私密 store 的 SDK 认证参数（OIDC 优先，回落长效 token） */
export function privateBlobAuth(): { storeId?: string; token?: string } {
  const storeId = process.env.PRIVATE_BLOB_STORE_ID;
  const token = process.env.PRIVATE_BLOB_READ_WRITE_TOKEN;
  return { ...(storeId ? { storeId } : {}), ...(token ? { token } : {}) };
}

/** 私密 store 未配置时给用户看的指引（直接透传到 App 界面） */
export const PRIVATE_BLOB_SETUP_HINT =
  '私密图库未配置私密存储：Vercel → 项目 → Storage → Create Storage → Blob，'
  + 'access 选 Private，Advanced Options 里把 prefix 填 PRIVATE_BLOB_，'
  + '点 Continue 自动连上项目（无需手写 token），配置后需 Redeploy 生效。';

/** 认证模式，仅用于自检展示 */
export function blobAuthMode(): 'oidc' | 'token' | null {
  if (process.env.BLOB_STORE_ID) return 'oidc';
  if (process.env.BLOB_READ_WRITE_TOKEN) return 'token';
  return null;
}

/** Hobby 额度（官方 pricing 页，随套餐可能调整，仅用于自检提示） */
export const BLOB_HOBBY_LIMITS = {
  storageGB: 1,
  simpleOps: 10_000,
  advancedOps: 2_000,
  dataTransferGB: 10,
} as const;

/**
 * 实测能否读写 store：list 一条就够（比 head 单文件更稳，不依赖已有对象）。
 * 返回 ready + 可直接展示给用户的中文 detail。
 */
export async function probeBlob(): Promise<{ ready: boolean; detail: string }> {
  if (!blobConfigured()) {
    return {
      ready: false,
      detail:
        '未检测到 Blob 配置：Vercel → 项目 → Storage → Create Database → Blob，'
        + 'access 选 Public，Store Name 随意（如 wardrobe），点 Continue 后自动连上项目，'
        + '无需手写任何 token。',
    };
  }
  try {
    await list({ limit: 1 });
    return { ready: true, detail: 'Blob 可读写（已实测 list 成功）。' };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (/suspend|blocked|403|forbidden/i.test(msg)) {
      return {
        ready: false,
        detail:
          '已配置但被 Vercel 拒绝：' + msg.slice(0, 120)
          + '。若 Storage → Store 详情里各项用量均未超限，多为 store 被封停，'
          + '只能提 Vercel Support 工单恢复（代码侧无解）。',
      };
    }
    return { ready: false, detail: '已配置但实测失败：' + msg.slice(0, 160) };
  }
}

/** /api/health 用的完整快照 */
export async function blobHealth() {
  const probe = await probeBlob();
  return {
    storage: 'vercel-blob',
    ready: probe.ready,
    authMode: blobAuthMode(),
    detail: probe.detail,
    limits: BLOB_HOBBY_LIMITS,
  };
}