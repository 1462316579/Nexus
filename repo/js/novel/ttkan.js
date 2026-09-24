// ==MiruExtension==
// @name         天天看小说
// @version      v0.0.1
// @author       Miru User
// @lang         zh-cn
// @license      MIT
// @package      org.ttkan.novel
// @type         fikushon
// @webSite      https://cn.ttkan.co
// @icon         https://cn.ttkan.co/favicon.ico
// @description  天天看小说搜索、分类与阅读
// ==/MiruExtension==

const BASE_URL = 'https://cn.ttkan.co';
const PAGE_SIZE = 24;
const CATEGORY_OPTIONS = {
  all: '全部', lianzai: '连载', suixuan: '随选', xuanhuan: '玄幻', dushi: '都市',
  xianxia: '仙侠', gudaiyanqing: '言情', chuanyuechongsheng: '穿越', youxi: '游戏',
  kehuan: '科幻', xuanyi: '悬疑', lingyi: '灵异', lishi: '历史', qingchun: '青春',
  junshi: '军事', jingji: '竞技', yanqing: '现言', qita: '其它',
};

export default class Ttkan extends Extension {
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

  decodeHtml(value) {
    return String(value || '')
      .replace(/&nbsp;|&#160;/gi, ' ')
      .replace(/&amp;/gi, '&').replace(/&lt;/gi, '<').replace(/&gt;/gi, '>')
      .replace(/&quot;/gi, '"').replace(/&#39;|&apos;/gi, "'");
  }

  stripHtml(value) {
    return this.decodeHtml(String(value || '')
      .replace(/<script[\s\S]*?<\/script>/gi, '')
      .replace(/<style[\s\S]*?<\/style>/gi, '')
      .replace(/<br\s*\/?>(?:\r?\n)?/gi, '\n')
      .replace(/<\/(?:p|div|article|section|li)>/gi, '\n')
      .replace(/<[^>]+>/g, ' '))
      .replace(/[ \t]+/g, ' ')
      .replace(/\n{3,}/g, '\n\n').trim();
  }

  absoluteUrl(url) {
    const value = this.decodeHtml(String(url || '').trim());
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
      if (!/\/novel\/chapters\//i.test(href)) continue;
      const title = this.stripHtml(match[2]);
      if (!title || title.length > 120 || /^(首页|排行|连载|随选|小说推荐)$/i.test(title)) continue;
      const url = this.absoluteUrl(href);
      if (seen[url]) continue;
      seen[url] = true;
      books.push({
        title,
        url,
        cover: this.absoluteUrl(attrs['data-src'] || attrs.src || ''),
        update: '',
      });
    }
    return books.slice(0, PAGE_SIZE);
  }

  createFilter(selected = {}) {
    return {
      category: {
        title: '分类', min: 0, max: 1,
        default: selected.category?.[0] || 'all', options: CATEGORY_OPTIONS,
      },
    };
  }

  async latest(page = 1, filter = {}) {
    const category = filter.category?.[0] || 'all';
    const path = category === 'all' ? '/novel/rank' : `/novel/class/${encodeURIComponent(category)}`;
    return this.parseBooks(await this.requestPage(path));
  }

  async search(keyword, page = 1, filter = {}) {
    const query = String(keyword || '').trim();
    if (!query) return this.latest(page, filter);
    return this.parseBooks(await this.requestPage(`/novel/search?q=${encodeURIComponent(query)}`));
  }

  extractNovelId(url) {
    return decodeURIComponent(String(url).match(/[?&]novel_id=([^&]+)/i)?.[1] || '');
  }

  async detail(url) {
    const pageUrl = String(url).split('?')[0];
    const html = await this.requestPage(pageUrl.replace(BASE_URL, '') || '/');
    const title = this.stripHtml(
      html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i)?.[1]
      || html.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1]
      || '天天看小说',
    ).replace(/^《|》.*$/g, (value) => value === '《' ? '' : value);
    const cover = this.absoluteUrl(html.match(/<img\b[^>]*(?:src|data-src)=["']([^"']+)["']/i)?.[1] || '');
    const novelId = pageUrl.match(/\/novel\/chapters\/([^/?#]+)/i)?.[1] || '';
    const urls = [];
    const seen = {};
    for (const match of html.matchAll(/<a\b([^>]*href=[^>]+)>\s*([\s\S]*?)<\/a>/gi)) {
      const attrs = this.parseAttributes(match[1]);
      const href = attrs.href || '';
      if (!/novel\/user\/page_direct\?[^"']*novel_id=/i.test(href)) continue;
      const name = this.stripHtml(match[2]);
      const chapterUrl = this.absoluteUrl(href);
      if (!name || seen[chapterUrl]) continue;
      seen[chapterUrl] = true;
      urls.push({ name, url: chapterUrl });
    }
    if (!urls.length && novelId) {
      urls.push({ name: '最新章节', url: `${BASE_URL}/novel/user/page_direct?novel_id=${encodeURIComponent(novelId)}&page=1` });
    }
    return { title, cover: cover || undefined, episodes: [{ title: '章节', urls }] };
  }

  async watch(url) {
    const html = await this.requestPage(String(url).replace(BASE_URL, '') || '/');
    const title = this.stripHtml(
      html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i)?.[1]
      || html.match(/<h2[^>]*>([\s\S]*?)<\/h2>/i)?.[1]
      || '小说章节',
    );
    const candidates = [
      /<(?:div|article)\b[^>]*(?:id|class)=["'][^"']*(?:novel[_-]?content|chapter[_-]?content|content|正文)[^"']*["'][^>]*>([\s\S]*?)<\/(?:div|article)>/i,
      /<article\b[^>]*>([\s\S]*?)<\/article>/i,
    ];
    let content = '';
    for (const pattern of candidates) {
      content = pattern.exec(html)?.[1] || '';
      if (content) break;
    }
    if (!content) content = html;
    const lines = this.stripHtml(content)
      .replace(/天天看小说|上一章|下一章|返回目录/g, '')
      .split(/\n+/)
      .map((line) => line.trim())
      .filter((line) => line && !/^广告|^本章未完/i.test(line));
    return { title, content: lines };
  }

  isLoginSupported() { return false; }
}
