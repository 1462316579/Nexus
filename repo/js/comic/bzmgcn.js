// ==MiruExtension==
// @name         包子漫画
// @version      v0.0.1
// @author       Miru User
// @lang         zh-cn
// @license      MIT
// @package      org.bzmgcn.comic
// @type         manga
// @webSite      https://cn.bzmgcn.com
// @icon         https://cn.bzmgcn.com/favicon.ico
// @description  包子漫画搜索、分类与阅读
// ==/MiruExtension==

const BASE_URL = 'https://cn.bzmgcn.com';
const PAGE_SIZE = 24;

export default class Bzmgcn extends Extension {
  async requestPage(path, options = {}) {
    const response = await this.request(path, {
      headers: {
        Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        Referer: `${BASE_URL}/`,
        ...options.headers,
      },
      ...options,
    });
    return String(response || '');
  }

  absoluteUrl(url) {
    const value = String(url || '').trim();
    if (!value) return '';
    if (/^https?:\/\//i.test(value)) return value;
    return `${BASE_URL}/${value.replace(/^\/+/, '')}`;
  }

  parseAttributes(tag) {
    const attrs = {};
    for (const match of String(tag).matchAll(/([\w-]+)\s*=\s*["']([^"']*)["']/gi)) {
      attrs[match[1].toLowerCase()] = match[2];
    }
    return attrs;
  }

  stripHtml(value) {
    return String(value || '')
      .replace(/<script[\s\S]*?<\/script>/gi, '')
      .replace(/<style[\s\S]*?<\/style>/gi, '')
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<\/(?:p|div|article|section|li|h[1-6])>/gi, '\n')
      .replace(/<[^>]+>/g, ' ')
      .replace(/&nbsp;/gi, ' ').replace(/&amp;/gi, '&')
      .replace(/&lt;/gi, '<').replace(/&gt;/gi, '>')
      .replace(/&#39;|&apos;/gi, "'").replace(/&quot;/gi, '"')
      .replace(/[ \t]+/g, ' ')
      .replace(/\n{3,}/g, '\n\n').trim();
  }

  parseComicItems(html) {
    const items = [];
    const seen = {};

    // 解析封面卡片列表，每个漫画包含在 <a class="comics-item"> 或类似的结构中
    // 页面结构: 封面图片 + 分类标签 + 标题 + 作者
    for (const match of String(html).matchAll(/(?:src|data-src)=["']([^"']+)["'][^>]*>/gi)) {
      const imgUrl = match[1];
      if (!imgUrl || !/doubaocdn\.com|static-tw\.bzmgcn\.com/i.test(imgUrl)) continue;

      // 找到 img 后的相邻文本结构
      const after = html.slice(match.index);
      const block = after.slice(0, 2000);

      // 提取标题
      let title = '';
      const titleMatch = block.match(/(?:alt|title)=["']([^"']+)["']/i)
        || block.match(/<[^>]*\b(?:title|name)=["']([^"']+)["']/i);
      if (titleMatch) title = titleMatch[1];

      // 查找指向 /comic/{slug} 的链接
      let comicUrl = '';
      for (const linkMatch of block.matchAll(/<a\b[^>]*href=["']([^"']*)["'][^>]*>([\s\S]*?)<\/a>/gi)) {
        const href = linkMatch[1];
        if (/^\/comic\//i.test(href) || /\/comic\//i.test(href)) {
          comicUrl = href;
          if (!title) {
            const stripText = this.stripHtml(linkMatch[2]);
            if (stripText && stripText.length < 100 && !/^\s*(?:分类|上一页|下一页|登录|注册|首页)/i.test(stripText)) {
              title = stripText;
            }
          }
          break;
        }
      }

      if (!comicUrl || !title) continue;
      const absUrl = this.absoluteUrl(comicUrl);
      if (seen[absUrl]) continue;
      seen[absUrl] = true;

      items.push({
        title,
        url: absUrl,
        cover: imgUrl,
        update: '',
      });

      if (items.length >= PAGE_SIZE) break;
    }

    // 备选：直接从所有 /comic/ 链接解析
    if (items.length === 0) {
      const seenLinks = {};
      for (const match of String(html).matchAll(/<a\b[^>]*href=["']([^"']*\/comic\/[^"']*)["'][^>]*>([\s\S]*?)<\/a>/gi)) {
        const href = match[1];
        const text = this.stripHtml(match[2]);
        if (!href || !text || text.length > 80 || /^(?:分类|排行榜|登录|注册|上一页|下一页|首页)$/i.test(text)) continue;
        const absUrl = this.absoluteUrl(href.split('?')[0]);
        if (seenLinks[absUrl]) continue;
        seenLinks[absUrl] = true;

        // 向前找同组图片
        let cover = '';
        const idx = html.indexOf(match[0]);
        if (idx > 0) {
          const prev = html.slice(Math.max(0, idx - 500), idx);
          const coverMatch = prev.match(/(?:src|data-src)=["']([^"']*)["']/i);
          if (coverMatch) cover = coverMatch[1];
        }

        items.push({
          title: text,
          url: absUrl,
          cover: cover || '',
          update: '',
        });
        if (items.length >= PAGE_SIZE) break;
      }
    }

    return items;
  }

  async latest(page = 1) {
    // 最新上架页面
    const html = await this.requestPage('/list/new');
    return this.parseComicItems(html);
  }

  async search(keyword, page = 1) {
    const query = String(keyword || '').trim();
    if (!query) return this.latest(page);

    // 尝试使用搜索功能（如果有的话）
    const searchHtml = await this.requestPage(`/search?q=${encodeURIComponent(query)}`).catch(() => '');
    const searchResults = this.parseComicItems(searchHtml);
    if (searchResults.length > 0) return searchResults;

    // 备选：搜索 API
    try {
      const apiResponse = await this.request(`/search/comic?q=${encodeURIComponent(query)}`, {
        headers: { Accept: 'application/json', Referer: `${BASE_URL}/` },
      });
      const data = typeof apiResponse === 'string' ? JSON.parse(apiResponse) : apiResponse;
      const comics = Array.isArray(data?.data) ? data.data : Array.isArray(data) ? data : [];
      return comics.map((c) => ({
        title: c.title || c.name || '',
        url: this.absoluteUrl(`/comic/${c.slug || c.id}`),
        cover: c.cover || c.cover_url || c.thumb || '',
        update: c.updated_at || c.latest_chapter || '',
      })).filter((item) => item.title);
    } catch (_) {}

    // 最后一招：在分类页搜索
    const classifyHtml = await this.requestPage('/classify');
    return this.parseComicItems(classifyHtml).filter((item) =>
      item.title.includes(query) || item.title.toLowerCase().includes(query.toLowerCase()),
    );
  }

  async detail(url) {
    const pageUrl = String(url).split('?')[0];
    const html = await this.requestPage(pageUrl.replace(BASE_URL, '') || '/');

    // 提取标题
    const title =
      this.stripHtml(html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i)?.[1] || '')
      || this.stripHtml(html.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1] || '')
      || '包子漫画';

    // 提取封面
    const cover =
      html.match(/<img[^>]*(?:class=["'][^"']*cover[^"']*["'])[^>]*(?:src|data-src)=["']([^"']*)["']/i)?.[1]
      || html.match(/<img[^>]*(?:src|data-src)=["']([^"']*cover[^"']*)["']/i)?.[1]
      || html.match(/"cover"\s*:\s*"([^"]*)"/i)?.[1]
      || '';

    // 解析章节列表
    const chapters = [];
    const seenChapters = {};

    // 方式1: 从链接中提取章节
    for (const match of html.matchAll(/<a\b[^>]*href=["']([^"']*)["'][^>]*>\s*([\s\S]*?)\s*<\/a>/gi)) {
      const href = match[1];
      const name = this.stripHtml(match[2]);

      // 章节链接格式: /user/page_direct?comic_id=xxx&section_slot=0&chapter_slot=N
      if (/user\/page_direct/i.test(href) && name && name.length < 100) {
        if (seenChapters[href]) continue;
        seenChapters[href] = true;
        chapters.push({ name, url: this.absoluteUrl(href) });
        continue;
      }

      // 其他可能的章节链接格式
      if (/\/chapter\//i.test(href) || /\/ep\//i.test(href) || /\/read\//i.test(href)) {
        if (seenChapters[href]) continue;
        seenChapters[href] = true;
        chapters.push({ name: name || '章节', url: this.absoluteUrl(href) });
      }
    }

    // 方式2: 从 JSON 数据中提取章节
    const jsonMatches = html.match(/window\.__INITIAL_STATE__\s*=\s*({[\s\S]*?});?\s*<\/script>/i)
      || html.match(/window\.__NUXT__\s*=\s*({[\s\S]*?});?\s*<\/script>/i)
      || html.match(/var\s+comic\s*=\s*({[\s\S]*?});/i)
      || html.match(/chapters?\s*[:=]\s*(\[[\s\S]*?\])/i);

    if (jsonMatches) {
      try {
        const jsonStr = jsonMatches[1] || jsonMatches[0];
        const jsonData = JSON.parse(jsonStr);
        const extractedChapters = this.extractChaptersFromJson(jsonData);
        for (const ch of extractedChapters) {
          if (!seenChapters[ch.url]) {
            seenChapters[ch.url] = true;
            chapters.push(ch);
          }
        }
      } catch (_) {}
    }

    // 按章节序号排序（降序，最新的在前）
    chapters.sort((a, b) => {
      const numA = parseInt(a.name.match(/\d+/)?.[0] || '0');
      const numB = parseInt(b.name.match(/\d+/)?.[0] || '0');
      return numB - numA;
    });

    return {
      title,
      cover: cover || undefined,
      episodes: [
        {
          title: '章节',
          urls: chapters,
        },
      ],
    };
  }

  extractChaptersFromJson(data) {
    const chapters = [];

    const walk = (obj) => {
      if (!obj || typeof obj !== 'object') return;
      if (Array.isArray(obj)) {
        obj.forEach(walk);
        return;
      }

      // 检测章节对象结构
      if (obj.url || obj.href || obj.link) {
        const url = obj.url || obj.href || obj.link;
        const name = obj.name || obj.title || obj.chapter_name || obj.chapterTitle || `章节 ${obj.id || obj.chapter || obj.slot || ''}`;
        if (url && (String(url).includes('page_direct') || String(url).includes('chapter') || String(url).includes('read'))) {
          chapters.push({ name, url: this.absoluteUrl(url) });
        }
      }

      // 递归遍历
      for (const key of Object.keys(obj)) {
        const val = obj[key];
        if (Array.isArray(val)) {
          val.forEach(walk);
        } else if (val && typeof val === 'object') {
          walk(val);
        }
      }
    };

    walk(data);
    return chapters;
  }

  async watch(url) {
    const pageUrl = String(url);
    const html = await this.requestPage(pageUrl.replace(BASE_URL, '') || '/');

    const images = [];

    // 方式1: 从 img 标签提取
    for (const match of html.matchAll(/<img\b[^>]*(?:src|data-src)=["']([^"']*)["']/gi)) {
      const imgUrl = match[1];
      if (imgUrl && !/base64|data:image|placeholder/i.test(imgUrl) && (imgUrl.includes('doubaocdn') || imgUrl.includes('bzmgcn') || /\.(jpg|jpeg|png|gif|webp)/i.test(imgUrl))) {
        images.push(imgUrl);
      }
    }

    // 方式2: 从 JSON 数据中提取图片
    const jsonMatches = html.match(/window\.__INITIAL_STATE__\s*=\s*({[\s\S]*?});?/i)
      || html.match(/window\.__NUXT__\s*=\s*({[\s\S]*?});?/i)
      || html.match(/pages\s*[:=]\s*(\[.*?\])/i);

    if (jsonMatches && images.length === 0) {
      try {
        const jsonStr = jsonMatches[1] || jsonMatches[0];
        const jsonData = JSON.parse(jsonStr);

        // 尝试多种可能的图片字段名
        const imgFields = ['images', 'pics', 'pages', 'photos', 'src', 'url', 'srcs', 'img_urls', 'image_urls'];
        const walkForImages = (obj) => {
          if (!obj || typeof obj !== 'object') return;
          for (const key of imgFields) {
            if (obj[key]) {
              const val = obj[key];
              if (Array.isArray(val)) {
                for (const item of val) {
                  const imgUrl = typeof item === 'string' ? item : (item.src || item.url || item.image || item);
                  if (imgUrl && String(imgUrl).length > 10 && !String(imgUrl).includes('base64')) {
                    images.push(imgUrl);
                  }
                }
              }
            }
          }
          for (const k of Object.keys(obj)) {
            if (Array.isArray(obj[k])) {
              obj[k].forEach(walkForImages);
            } else if (obj[k] && typeof obj[k] === 'object') {
              walkForImages(obj[k]);
            }
          }
        };
        walkForImages(jsonData);
      } catch (_) {}
    }

    if (images.length === 0) {
      // 备选：从 srcset 或 data-src 提取
      for (const match of html.matchAll(/(?:srcset|data-src|data-original)=["']([^"']*)["']/gi)) {
        const srcset = match[1];
        const parts = srcset.split(/[,\s]+/);
        for (const part of parts) {
          if (/^https?:\/\//.test(part) && (part.includes('doubaocdn') || /\.(jpg|jpeg|png|gif|webp)/i.test(part))) {
            images.push(part);
          }
        }
      }
    }

    // 去重
    const uniqueImages = [...new Set(images)];

    if (uniqueImages.length === 0) {
      throw new Error('未找到漫画图片，请检查页面是否需要登录或网站结构已变更。');
    }

    return {
      urls: uniqueImages,
      headers: { Referer: `${BASE_URL}/` },
    };
  }

  isLoginSupported() {
    return false;
  }
}