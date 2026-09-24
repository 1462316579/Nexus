// ==MiruExtension==
// @name         多多影视
// @version      v0.0.2
// @author       Miru User
// @lang         zh-cn
// @license      MIT
// @package      org.duoduo.tv
// @type         bangumi
// @webSite      https://323433ssdfd.top
// @icon         https://323433ssdfd.top/favicon.ico
// @description  多多影视分类、搜索与播放
// ==/MiruExtension==

const BASE_URL = 'https://323433ssdfd.top';
const WEB_SIGN = 'ddtvf65f3a83d6d9ad6f';
const CLIENT = '8f3d2a1c7b6e5d4c9a0b1f2e3d4c5b6a';

// 播放解码签名所需的内置常量（由站点 WASM 提取，全设备固定）
const SIGN_FINGER =
  'WF-2c064bc5b3400788f31b848849bc3a60f835423ba2dfe69d7ea93974c216e4f2';
const SIGN_SK =
  'WEB-50a8e9c84a1dc05669a692ded99a2dac46527229e607a7be15db88dbc59059d1';
const SIGN_ID = 'com.web.player';

const TYPE_NAMES = ['电影', '剧集', '动漫', '综艺'];

// 插件返回给 UI 的图片请求 headers：带 Mozilla UA 让 CDN 接受
// 注意：不统一加 Referer，因为 iqiyi/youku 等带 duoduo 域 Referer 会 403
const IMAGE_HEADERS = {
  'User-Agent':
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0',
};

// 常用筛选选项（来自对真实接口聚合 + 探测验证，服务端精确匹配）
const AREA_OPTIONS = {
  中国大陆: '中国大陆', 内地: '内地', '中国香港': '中国香港', 香港: '香港',
  美国: '美国', 韩国: '韩国', 日本: '日本', 英国: '英国', 菲律宾: '菲律宾',
  加拿大: '加拿大', 澳大利亚: '澳大利亚', 冰岛: '冰岛', 意大利: '意大利',
  欧美: '欧美', 其他: '其他',
};

const CLASS_OPTIONS = {
  剧情: '剧情', 动作: '动作', 喜剧: '喜剧', 犯罪: '犯罪', 惊悚: '惊悚',
  动画: '动画', 冒险: '冒险', 科幻: '科幻', 悬疑: '悬疑', 爱情: '爱情',
  历史: '历史', 恐怖: '恐怖', 古装: '古装', 运动: '运动', 战争: '战争',
  奇幻: '奇幻', 武侠: '武侠', 灾难: '灾难', 家庭: '家庭',
};

// 年份：2026 往回 20 年
function buildYearOptions() {
  const now = new Date();
  const start = now.getFullYear() + 1; // 明年也常见（预告）
  const end = start - 25;
  const result = {};
  for (let y = start; y >= end; y--) result[String(y)] = String(y);
  return result;
}

export default class Duoduo extends Extension {
  commonHeaders(extra = {}) {
    return {
      'X-Client': CLIENT,
      'web-sign': WEB_SIGN,
      Referer: `${BASE_URL}/`,
      ...extra,
    };
  }

  async requestApi(path, query = {}) {
    const params = Object.entries(query)
      .filter(([, value]) => value !== '' && value != null)
      .map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(value)}`)
      .join('&');
    const response = await this.request(
      `/api.php/web${path}${params ? `?${params}` : ''}`,
      {
        headers: this.commonHeaders({
          Accept: 'application/json',
        }),
      },
    );
    const data = typeof response === 'string' ? JSON.parse(response) : response;
    if (data?.code !== 200) {
      throw new Error(data?.msg || '多多影视接口请求失败');
    }
    return data;
  }

  normalizeVideo(video) {
    const id = video?.vod_id ?? video?.id;
    const rawCover = video?.vod_pic || video?.cover || '';
    const cover =
      typeof rawCover === 'string' &&
      (rawCover.startsWith('http://') || rawCover.startsWith('https://'))
        ? rawCover
        : '';
    return {
      title: video?.vod_name || video?.name || '',
      url: `/detail/${id}`,
      cover,
      headers: cover ? IMAGE_HEADERS : undefined,
      update: video?.vod_remarks || video?.vod_serial || '',
    };
  }

  createFilter(selected = {}) {
    const pick = (key, fallback) => selected[key]?.[0] || fallback;
    const yearOptions = buildYearOptions();
    return {
      type: {
        title: '分类',
        min: 0,
        max: 1,
        default: pick('type', TYPE_NAMES[0]),
        options: {
          电影: '电影',
          剧集: '剧集',
          动漫: '动漫',
          综艺: '综艺',
        },
      },
      area: {
        title: '地区',
        min: 0,
        max: 1,
        default: pick('area', ''),
        options: AREA_OPTIONS,
      },
      class: {
        title: '类型',
        min: 0,
        max: 1,
        default: pick('class', ''),
        options: CLASS_OPTIONS,
      },
      year: {
        title: '年份',
        min: 0,
        max: 1,
        default: pick('year', ''),
        options: yearOptions,
      },
      sort: {
        title: '排序',
        min: 0,
        max: 1,
        default: pick('sort', 'hits'),
        options: {
          hits: '最热',
          time: '最新',
        },
      },
    };
  }

  async fetchVideos(page = 1, filter = {}) {
    const typeName = filter.type?.[0] || '';
    const sort = filter.sort?.[0] || 'hits';
    const area = filter.area?.[0] || '';
    const cls = filter.class?.[0] || '';
    const year = filter.year?.[0] || '';
    const lang = filter.lang?.[0] || '';
    const data = await this.requestApi('/filter/vod', {
      type_name: typeName,
      page,
      sort,
      area,
      class: cls,
      year,
      lang,
    });
    const items = Array.isArray(data.data) ? data.data : [];
    return items
      .map((video) => this.normalizeVideo(video))
      .filter((video) => video.title && !video.url.endsWith('/undefined'));
  }

  async latest(page = 1) {
    // 未选择筛选条件时默认展示电影分类（与 createFilter 的默认选中项一致）
    return this.fetchVideos(page, { type: ['电影'], sort: ['hits'] });
  }

  async search(keyword, page = 1, filter = {}) {
    filter = filter || {};
    if (keyword && String(keyword).trim()) {
      const data = await this.requestApi('/search/index', {
        wd: String(keyword).trim(),
        page,
        limit: 24,
      });
      const items = Array.isArray(data.data)
        ? data.data
        : data.data?.list || data.data?.videos || [];
      return items
        .map((video) => this.normalizeVideo(video))
        .filter((video) => video.title && !video.url.endsWith('/undefined'));
    }
    // 关键词为空且带有筛选条件时，作为分类列表使用
    return this.fetchVideos(page, filter);
  }

  stripHtml(content) {
    return String(content || '')
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<[^>]+>/g, '')
      .replace(/&nbsp;/g, ' ')
      .replace(/&#39;|&apos;/g, "'")
      .replace(/&quot;/g, '"')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&amp;/g, '&')
      .trim();
  }

  async fetchDetail(id) {
    const data = await this.requestApi('/vod/get_detail', { vod_id: id });
    if (!Array.isArray(data.data) || !data.data[0]) {
      throw new Error('未获取到影片详情');
    }
    return { video: data.data[0], players: data.vodplayer || [] };
  }

  async detail(url) {
    const id = String(url).split('/').filter(Boolean).pop();
    const { video, players } = await this.fetchDetail(id);

    const playFrom = String(video.vod_play_from || '').split('$$$');
    const playUrl = String(video.vod_play_url || '').split('$$$');

    // 站点返回的线路显示名与排序
    const playerMap = {};
    for (const player of players) {
      if (player?.from) {
        playerMap[player.from] = {
          show: player.show || player.from,
          sort: parseFloat(player.sort) || 0,
        };
      }
    }
    const lineOrder = playFrom
      .map((from, index) => ({
        from,
        index,
        sort: playerMap[from]?.sort ?? -1,
      }))
      .sort((a, b) => b.sort - a.sort)
      .map((item) => item.index);

    const episodes = [];
    for (const lineIndex of lineOrder) {
      const line = playUrl[lineIndex];
      if (!line) continue;
      const urls = [];
      const parts = line.split('#');
      for (let epIndex = 0; epIndex < parts.length; epIndex++) {
        const item = parts[epIndex];
        const splitIndex = item.indexOf('$');
        if (splitIndex < 0) continue;
        const name = item.slice(0, splitIndex) || `第${epIndex + 1}集`;
        const token = item.slice(splitIndex + 1);
        if (!token) continue;
        urls.push({
          name,
          url: `/play/${id}/${lineIndex}/${epIndex}`,
        });
      }
      if (urls.length) {
        const from = playFrom[lineIndex];
        episodes.push({
          title: playerMap[from]?.show || from || `线路${lineIndex + 1}`,
          urls,
        });
      }
    }

    const descParts = [
      video.vod_year ? `年份：${video.vod_year}` : '',
      Array.isArray(video.vod_area) && video.vod_area.length
        ? `地区：${video.vod_area.join(' ')}`
        : '',
      Array.isArray(video.vod_class) && video.vod_class.length
        ? `类型：${video.vod_class.join(' ')}`
        : '',
      video.vod_actor ? `主演：${video.vod_actor}` : '',
      video.vod_director ? `导演：${video.vod_director}` : '',
      video.vod_content ? `\n${this.stripHtml(video.vod_content)}` : '',
    ].filter(Boolean);

    return {
      title: video.vod_name || '多多影视',
      cover: video.vod_pic || undefined,
      desc: descParts.join('\n') || undefined,
      episodes,
    };
  }

  // ---- protobuf 手工编解码（QuickJS 无 WASM/ArrayBuffer 通道） ----
  pbVarint(bytes, value) {
    // 时间戳超过 32 位，按无符号 64 位 varint 逐 7 位编码
    let v = Math.floor(Number(value));
    while (v > 0x7f) {
      bytes.push((v & 0x7f) | 0x80);
      v = Math.floor(v / 128);
    }
    bytes.push(v & 0x7f);
  }

  pbString(bytes, field, str) {
    bytes.push((field << 3) | 2);
    this.pbVarint(bytes, str.length);
    for (let i = 0; i < str.length; i++) {
      bytes.push(str.charCodeAt(i) & 0xff);
    }
  }

  pbReadVarint(bytes, cursor) {
    let result = 0;
    let shift = 0;
    let byte;
    do {
      byte = bytes[cursor.i++];
      result += (byte & 0x7f) * Math.pow(2, shift);
      shift += 7;
    } while (byte & 0x80);
    return result;
  }

  pbDecode(bytes) {
    const cursor = { i: 0 };
    const result = {};
    while (cursor.i < bytes.length) {
      const tag = this.pbReadVarint(bytes, cursor);
      const field = tag >> 3;
      const wireType = tag & 7;
      if (wireType === 2) {
        const length = this.pbReadVarint(bytes, cursor);
        let str = '';
        for (let j = 0; j < length; j++) {
          str += String.fromCharCode(bytes[cursor.i++]);
        }
        result[field] = str;
      } else if (wireType === 0) {
        result[field] = this.pbReadVarint(bytes, cursor);
      } else {
        throw new Error('不支持的 protobuf 字段类型');
      }
    }
    return result;
  }

  randomNonce() {
    const hex = '0123456789abcdef';
    let output = '';
    for (let i = 0; i < 32; i++) {
      output += hex[Math.floor(Math.random() * 16)];
    }
    return output;
  }

  buildDecodeRequest(token, from) {
    const nonce = this.randomNonce();
    const time = Date.now();
    const query =
      `finger=${SIGN_FINGER}` +
      `&id=${SIGN_ID}` +
      `&nonce=${nonce}` +
      `&sk=${SIGN_SK}` +
      `&time=${time}` +
      '&v=1';
    // 签名：SHA256(查询串) 后转大写十六进制
    const sign = CryptoJS.SHA256(query).toString().toUpperCase();

    const bytes = [];
    this.pbString(bytes, 1, token);
    this.pbString(bytes, 2, from);
    this.pbVarint(bytes, 3 << 3);
    this.pbVarint(bytes, time);
    this.pbString(bytes, 4, nonce);
    this.pbString(bytes, 5, sign);
    this.pbString(bytes, 6, SIGN_ID);
    this.pbVarint(bytes, 7 << 3);
    this.pbVarint(bytes, 1);
    return bytes;
  }

  async watch(url) {
    const parts = String(url).split('/').filter(Boolean);
    // /play/{vodId}/{lineIndex}/{epIndex}
    const vodId = parts[1];
    const lineIndex = parseInt(parts[2], 10);
    const epIndex = parseInt(parts[3], 10);
    if (
      vodId == null ||
      Number.isNaN(lineIndex) ||
      Number.isNaN(epIndex)
    ) {
      throw new Error('播放信息缺失，请重新进入详情页');
    }

    const { video } = await this.fetchDetail(vodId);
    const playFrom = String(video.vod_play_from || '').split('$$$');
    const playUrl = String(video.vod_play_url || '').split('$$$');
    const from = playFrom[lineIndex];
    const episodeLine = playUrl[lineIndex];
    if (!from || !episodeLine) {
      throw new Error('播放线路不存在，可能已下线');
    }
    const episode = episodeLine.split('#')[epIndex];
    if (!episode) {
      throw new Error('剧集不存在，可能已下线');
    }
    const splitIndex = episode.indexOf('$');
    const token = splitIndex >= 0 ? episode.slice(splitIndex + 1) : '';
    if (!token) {
      throw new Error('播放令牌为空，无法解码');
    }

    const body = this.buildDecodeRequest(token, from);
    let response;
    try {
      response = await this.request('/api.php/web/decode/url', {
        method: 'post',
        binary: true,
        data: body,
        headers: this.commonHeaders({
          Accept: 'application/x-protobuf',
          'Content-Type': 'application/x-protobuf',
        }),
      });
    } catch (error) {
      throw new Error(`播放解码请求失败：${error}`);
    }

    if (!Array.isArray(response)) {
      throw new Error('播放解码返回了无效数据');
    }
    let decoded;
    try {
      decoded = this.pbDecode(response);
    } catch (error) {
      throw new Error(`播放解码数据解析失败：${error}`);
    }
    if (decoded[1] !== 1 || !decoded[3]) {
      throw new Error(decoded[2] || '播放解码失败，请更换线路或稍后再试');
    }

    const playUrlReal = decoded[3];
    return {
      type: /\.m3u8(?:[?#]|$)/i.test(playUrlReal) ? 'hls' : 'mp4',
      url: playUrlReal,
      headers: {
        Referer: `${BASE_URL}/`,
      },
    };
  }

  isLoginSupported() {
    return false;
  }
}
