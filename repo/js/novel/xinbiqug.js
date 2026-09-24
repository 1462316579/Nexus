// ==MiruExtension==
// @name         新笔趣阁
// @version      v0.0.1
// @author       Miru User
// @lang         zh-cn
// @license      MIT
// @package      org.xinbiqug.novel
// @type         fikushon
// @webSite      https://www.xinbiqug.com
// @icon         https://www.xinbiqug.com/favicon.ico
// @description  新笔趣阁小说搜索、分类与阅读
// ==/MiruExtension==

const BASE_URL = 'https://www.xinbiqug.com';
const PAGE_SIZE = 20;
const CATEGORY_OPTIONS = {
  all: '全部小说', mofa: '魔法玄幻', xiuzhen: '修真武侠', dushi: '都市校园',
  lishi: '历史军事', lingyi: '灵异侦探', wangyou: '网游耽美', qita: '其他小说',
};

export default class Xinbiqug extends Extension {
  async requestPage(path) {
    const response = await this.request(path, {
      headers: { Accept: 'text/html,application/xhtml+xml', Referer: `${BASE_URL}/` },
    });
    return String(response || '');
  }

  parseAttributes(tag) {
    const attrs = {};
    for (const match of String(tag).matchAll(/([\w-]+)\s*=\s*["']([^"']*)["']/g)) {
      attrs[match[1].toLowerCase()] = match[2];
    }
    return attrs;
  }

  stripHtml(value) {
    return String(value || '')
      .replace(/<script[\s\S]*?<\/script>/gi, '')
      .replace(/<style[\s\S]*?<\/style>/gi, '')
      .replace(/<br\s*\/?>(?:\r?\n)?/gi, '\n')
      .replace(/<\/(?:p|div|article|section)>/gi, '\n')
      .replace(/<[^>]+>/g, ' ')
      .replace(/&nbsp;/gi, ' ').replace(/&amp;/gi, '&')
      .replace(/&lt;/gi, '<').replace(/&gt;/gi, '>')
      .replace(/&#39;|&apos;/gi, "'").replace(/&quot;/gi, '"')
      .replace(/[ \t]+/g, ' ')
      .replace(/\n{3,}/g, '\n\n').trim();
  }

  absoluteUrl(url) {
    const value = String(url || '').trim();
    if (!value) return '';
    if (/^https?:\/\//i.test(value)) return value;
    return `${BASE_URL}/${value.replace(/^\/+/, '')}`;
  }

  parseBooks(html) {
    const books = [];
    const seen = {};
    for (const match of String(html).matchAll(/<a\b([^>]*href=[^>]+)>\s*([\s\S]*?)<\/a>/gi)) {
      const attrs = this.parseAttributes(match[1]);
      const href = attrs.href || '';
      if (!/(?:\/book\/|book|novel|\/\d+\.html|\/info\/)/i.test(href)) continue;
      const title = this.stripHtml(match[2]);
      if (!title || title.length > 80 || /^(首页|分类|排行榜|登录|注册|下一页|上一页)$/i.test(title)) continue;
      const url = this.absoluteUrl(href);
      if (seen[url]) continue;
      seen[url] = true;
      books.push({ title, url, cover: this.absoluteUrl(attrs['data-src'] || attrs.src || ''), update: '' });
    }
    return books.slice(0, PAGE_SIZE);
  }

  createFilter(selected = {}) {
    return { category: { title: '分类', min: 0, max: 1, default: selected.category?.[0] || 'all', options: CATEGORY_OPTIONS } };
  }

  async latest(page = 1, filter = {}) {
    const category = filter.category?.[0] || 'all';
    const path = category === 'all' ? '/' : `/${category}.html`;
    return this.parseBooks(await this.requestPage(path));
  }

  async search(keyword, page = 1, filter = {}) {
    const query = String(keyword || '').trim();
    if (!query) return this.latest(page, filter);

    // 当前站点搜索表单仍指向 /?wd=，但服务端会返回 404；优先尝试该入口，失败后使用站点地图。
    try {
      const html = await this.requestPage(`/?wd=${encodeURIComponent(query)}`);
      const results = this.parseBooks(html);
      if (results.length) return results;
    } catch (_) {}

    const sitemap = await this.requestPage('/sitemap.html');
    return this.parseBooks(sitemap).filter((book) =>
      book.title.toLowerCase().includes(query.toLowerCase()),
    ).slice(0, PAGE_SIZE);
  }

  async detail(url) {
    const pageUrl = String(url).split('?')[0];
    const pagePath = pageUrl.replace(BASE_URL, '') || '/';
    const html = await this.requestPage(pagePath);
    const title = this.stripHtml(html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i)?.[1] || html.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1] || '新笔趣阁小说');
    const cover = this.absoluteUrl(html.match(/<img\b[^>]*(?:src|data-src)=["']([^"']+)["']/i)?.[1] || '');
    const bookBase = pagePath.match(/^(\/book\/[^/]+\/)/i)?.[1] || '';
    const urls = [];
    const seen = {};
    for (const match of html.matchAll(/<a\b([^>]*href=[^>]+)>\s*([\s\S]*?)<\/a>/gi)) {
      const attrs = this.parseAttributes(match[1]);
      const name = this.stripHtml(match[2]);
      const href = attrs.href || '';
      if (!href || !name || name.length > 100 || !/(?:chapter|\d+\.html|read)/i.test(href)) continue;
      const chapterUrl = /^https?:\/\//i.test(href)
        ? href
        : `${BASE_URL}/${(href.startsWith('/') ? href.slice(1) : `${bookBase}${href}`).replace(/^\/+/, '')}`;
      if (seen[chapterUrl]) continue;
      seen[chapterUrl] = true;
      urls.push({ name, url: chapterUrl });
    }
    return { title, cover: cover || undefined, episodes: [{ title: '章节', urls }] };
  }

  async watch(url) {
    const chapterUrl = String(url);
    const html = await this.requestPage(chapterUrl.replace(BASE_URL, '') || '/');
    const matched = html.match(/<(?:div|article)\b[^>]*(?:id|class)=["'][^"']*(?:content|正文|chapter)[^"']*["'][^>]*>([\s\S]*?)<\/(?:div|article)>/i);
    const content = matched?.[1] || html;
    const text = this.stripHtml(content)
      .replace(/\s*\n\s*/g, '\n')
      .replace(/[ \t]+/g, ' ')
      .trim();
    return {
      title: this.stripHtml(html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i)?.[1] || '小说章节'),
      content: text.split(/\n+/).map((line) => line.trim()).filter(Boolean),
    };
  }

  isLoginSupported() { return false; }
}
