// ==MiruExtension==
// @name         5sing原创音乐
// @version      v0.0.1
// @author       Miru User
// @lang         zh-cn
// @license      MIT
// @package      org.5sing.kugou
// @type         music
// @webSite      https://5sing.kugou.com
// @icon         https://5sing.kugou.com/favicon.ico
// @description  5sing原创音乐搜索、分类与播放
// ==/MiruExtension==

const BASE_URL = 'https://5sing.kugou.com';
const PAGE_SIZE = 24;

export default class FiveSing extends Extension {
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

  parseSongItems(html, type = 'all') {
    const items = [];
    const seen = {};

    // 解析歌曲列表
    // 格式1: 链接 /yc/{id}.html, /fc/{id}.html, /bz/{id}.html
    for (const match of String(html).matchAll(/<a\b[^>]*href=["']([^"']*\/([ycfb][cy])\/(\d+)\.html)["'][^>]*>\s*([\s\S]*?)<\/a>/gi)) {
      const fullUrl = match[1];
      const songType = match[2]; // yc, fc, bz
      const songId = match[3];
      const text = this.stripHtml(match[4]).trim();

      if (!text || text.length > 100 || /^(?:更多|播放|下载|试听)$/i.test(text)) continue;
      if (type !== 'all' && songType !== type) continue;

      const url = this.absoluteUrl(fullUrl);
      if (seen[url]) continue;
      seen[url] = true;

      // 向前找封面图
      let cover = '';
      let author = '';
      let title = text;

      const idx = html.indexOf(match[0]);
      if (idx > 0) {
        const prev = html.slice(Math.max(0, idx - 800), idx);
        // 找封面
        const coverMatch = prev.match(/(?:src|data-src)=["']([^"']*doubaocdn[^"']*)["']/i);
        if (coverMatch) cover = coverMatch[1];
        // 找作者
        const authorMatch = prev.match(/href=["']([^"']*\/(\d+)\.html)["'][^>]*>([^<]+)<\/a>/);
        if (authorMatch) author = this.stripHtml(authorMatch[3]);
      }

      // 标题可能包含额外信息，需要清理
      title = title.replace(/\s*【[^】]*】\s*/g, ' ').replace(/\s+/g, ' ').trim();

      items.push({
        title,
        url,
        cover: cover || '',
        artist: author || '',
      });

      if (items.length >= PAGE_SIZE) break;
    }

    // 格式2: 从列表数据解析（通用模式）
    if (items.length === 0) {
      // 提取所有 doubaocdn 图片及其后的链接
      const imgPattern = /(?:src|data-src)=["']([^"']*doubaocdn[^"']*)["']/gi;
      for (const imgMatch of String(html).matchAll(imgPattern)) {
        const imgUrl = imgMatch[1];
        if (!imgUrl) continue;

        const imgIdx = html.indexOf(imgMatch[0]);
        if (imgIdx < 0) continue;

        // 查找该图片附近最近的歌曲链接
        const after = html.slice(imgIdx, imgIdx + 1500);
        const linkMatch = after.match(/href=["']([^"']*\/[yfcbz][yce]\/\d+\.html)["'][^>]*>\s*([^<]+)<\/a>/i);

        if (linkMatch) {
          const url = this.absoluteUrl(linkMatch[1]);
          const title = this.stripHtml(linkMatch[2]).trim();
          if (title && !seen[url]) {
            seen[url] = true;
            items.push({ title, url, cover: imgUrl, artist: '' });
            if (items.length >= PAGE_SIZE) break;
          }
        }
      }
    }

    return items;
  }

  async latest(page = 1) {
    // 首页原创推荐
    const html = await this.requestPage('/');
    return this.parseSongItems(html);
  }

  async search(keyword, page = 1) {
    const query = String(keyword || '').trim();
    if (!query) return this.latest(page);

    // 使用5sing搜索
    const searchUrl = `/search?keyword=${encodeURIComponent(query)}`;
    const html = await this.requestPage(searchUrl);
    const results = this.parseSongItems(html);

    if (results.length > 0) return results;

    // 备选：搜索 API
    try {
      const apiResponse = await this.request(`/search/song?q=${encodeURIComponent(query)}&page=${page}`, {
        headers: { Accept: 'application/json', Referer: `${BASE_URL}/` },
      });
      const data = typeof apiResponse === 'string' ? JSON.parse(apiResponse) : apiResponse;
      const songs = Array.isArray(data?.list) ? data.list : Array.isArray(data) ? data : [];
      return songs.map((s) => ({
        title: s.songname || s.name || '',
        url: this.absoluteUrl(`/${s.type || 'yc'}/${s.id}`),
        cover: s.img || s.cover || s.fabricUrl || '',
        artist: s.nickname || s.author || '',
      })).filter((item) => item.title);
    } catch (_) {}

    // 最后尝试：首页搜索
    const homeHtml = await this.requestPage('/');
    return this.parseSongItems(homeHtml).filter((item) =>
      item.title.includes(query) || item.artist.includes(query),
    );
  }

  async detail(url) {
    const pageUrl = String(url).split('?')[0];
    const html = await this.requestPage(pageUrl.replace(BASE_URL, '') || '/');

    // 提取标题
    const title =
      this.stripHtml(html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i)?.[1] || '')
      || this.stripHtml(html.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1] || '')
      || '5sing音乐';

    // 提取封面
    const cover =
      html.match(/<img[^>]*class=["'][^"']*(?:cover|img)[^"']*["'][^>]*(?:src|data-src)=["']([^"']*)["']/i)?.[1]
      || html.match(/<img[^>]*(?:src|data-src)=["']([^"']*cover[^"']*)["']/i)?.[1]
      || html.match(/"cover"\s*:\s*"([^"]*)"/i)?.[1]
      || '';

    // 提取作者
    const author =
      this.stripHtml(html.match(/作者[^:：]*[:：]\s*<a[^>]*>([^<]+)<\/a>/i)?.[1] || '')
      || this.stripHtml(html.match(/歌手[^:：]*[:：]\s*<a[^>]*>([^<]+)<\/a>/i)?.[1] || '')
      || this.stripHtml(html.match(/nickname["\s:]+([^,}]+)/i)?.[1] || '');

    // 构建歌曲信息（详情页本身就是一首歌）
    const songUrl = this.absoluteUrl(pageUrl.replace(BASE_URL, '') || '/');

    return {
      title,
      cover: cover || undefined,
      artist: author || undefined,
      tracks: [{
        title,
        url: songUrl,
        artist,
      }],
    };
  }

  async music(url) {
    const pageUrl = String(url);
    const html = await this.requestPage(pageUrl.replace(BASE_URL, '') || '/');

    let songUrl = '';
    let songName = '';
    let singer = '';

    // 尝试从页面提取音频URL
    // 方式1: 从 JSON 数据提取
    const jsonMatches = html.match(/window\.__INITIAL_STATE__\s*=\s*({[\s\S]*?});?/i)
      || html.match(/var\s+song\s*=\s*({[\s\S]*?});/i)
      || html.match(/"song"\s*:\s*({[\s\S]*?})/i)
      || html.match(/"musicUrl"\s*:\s*"([^"]*)"/i)
      || html.match(/"downurl"\s*:\s*"([^"]*)"/i);

    if (jsonMatches) {
      try {
        const jsonStr = jsonMatches[1] || jsonMatches[0];
        const jsonData = JSON.parse(jsonStr);

        // 尝试多种可能的音频URL字段
        const audioFields = ['musicUrl', 'downurl', 'url', 'mp3', 'songurl', 'song_url', 'audio', 'playurl', 'play_url'];
        for (const field of audioFields) {
          if (jsonData[field]) {
            songUrl = jsonData[field];
            break;
          }
        }

        // 提取歌曲名和歌手
        songName = jsonData.songname || jsonData.name || jsonData.title || '';
        singer = jsonData.nickname || jsonData.singer || jsonData.author || '';
      } catch (_) {}
    }

    // 方式2: 从 HTML 中提取音频源
    if (!songUrl) {
      const audioMatch = html.match(/<audio[^>]*src=["']([^"']*)["']/i)
        || html.match(/<source[^>]*src=["']([^"']*)["']/i)
        || html.match(/["']([^"']*\.mp3[^"']*)["']/i)
        || html.match(/play\(['"]([^'"]+)['"]\)/i);

      if (audioMatch) {
        songUrl = audioMatch[1];
      }
    }

    // 方式3: 尝试从链接提取歌曲ID并构建播放URL
    if (!songUrl) {
      const songIdMatch = pageUrl.match(/\/([yfcbz][yce])\/(\d+)\.html/i);
      if (songIdMatch) {
        const songType = songIdMatch[1];
        const songId = songIdMatch[2];

        // 尝试 API 获取播放地址
        try {
          const apiData = await this.request(`/api/song/${songId}`, {
            headers: { Accept: 'application/json', Referer: `${BASE_URL}/` },
          });
          const parsed = typeof apiData === 'string' ? JSON.parse(apiData) : apiData;
          if (parsed.data?.mp3 || parsed.data?.url) {
            songUrl = parsed.data.mp3 || parsed.data.url;
          }
        } catch (_) {}
      }
    }

    // 最后尝试：使用 5sing API 获取歌曲信息
    if (!songUrl) {
      const songIdMatch = pageUrl.match(/\/([yfcbz][yce])\/(\d+)\.html/i);
      if (songIdMatch) {
        const songType = songIdMatch[1];
        const songId = songIdMatch[2];

        try {
          // 尝试多种可能的API端点
          const apiEndpoints = [
            `/api/v1/song/${songId}`,
            `/api/songinfo/${songId}`,
            `/song/getinfo?id=${songId}&type=${songType}`,
          ];

          for (const endpoint of apiEndpoints) {
            try {
              const resp = await this.request(endpoint, {
                headers: { Accept: 'application/json', Referer: `${BASE_URL}/` },
              });
              const data = typeof resp === 'string' ? JSON.parse(resp) : resp;
              if (data?.data?.mp3 || data?.data?.url || data?.url) {
                songUrl = data.data?.mp3 || data.data?.url || data.url;
                if (data.songname) songName = data.songname;
                if (data.nickname) singer = data.nickname;
                break;
              }
            } catch (_) {
              continue;
            }
          }
        } catch (_) {}
      }
    }

    if (!songUrl) {
      throw new Error('未能获取音频地址，请检查歌曲是否存在或需要登录。');
    }

    // 提取歌曲名称
    if (!songName) {
      const titleMatch = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
      if (titleMatch) {
        songName = this.stripHtml(titleMatch[1]).replace(/\s*[-_].*5sing.*$/i, '').trim();
      }
    }

    return {
      url: songUrl,
      name: songName || '未知歌曲',
      singer: singer || '',
    };
  }

  isLoginSupported() {
    return false;
  }
}