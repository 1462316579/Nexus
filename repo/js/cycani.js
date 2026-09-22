// ==MiruExtension==
// @name         次元城动画
// @version      v0.0.1
// @author       Miru User
// @lang         zh-cn
// @license      MIT
// @package      org.cycani
// @type         bangumi
// @webSite      https://www.cycani.org
// @icon         https://www.cycani.org/brand/bangumi-favicon.ico
// @description  次元城动画分类、筛选与登录播放
// ==/MiruExtension==

const BASE_URL = 'https://www.cycani.org';
const PAGE_SIZE = 24;

export default class Cycani extends Extension {
  async api(path, query = {}) {
    const params = Object.entries(query)
      .filter(([, value]) => value !== '' && value != null)
      .map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(value)}`)
      .join('&');
    const response = await this.request(`/api${path}?${params}`, {
      headers: {
        'X-App-Name': 'cyc_web',
        'X-App-Version': 'cycweb',
        'X-Time-Zone': 'Asia/Shanghai',
        Referer: `${BASE_URL}/category`,
        Accept: 'application/json',
      },
    });
    const data = typeof response === 'string' ? JSON.parse(response) : response;
    if (data?.code !== 0) throw new Error(data?.msg || `API error: ${data?.code}`);
    return data.data ?? data;
  }

  async zones() {
    const data = await this.api('/video-zones');
    const zones = Array.isArray(data) ? data : data?.list ?? data?.zones ?? data?.items ?? [];
    return zones.map((zone) => ({
      ...zone,
      filters: zone.filters ?? {},
    }));
  }

  async createFilter(selected = {}) {
    const zones = await this.zones();
    const zoneOptions = Object.fromEntries(
      zones.filter((zone) => zone?.id != null)
        .map((zone) => [String(zone.id), zone.name || `分区 ${zone.id}`]),
    );
    const zoneId = selected.zone_id?.[0] || Object.keys(zoneOptions)[0] || '';
    const current = zones.find((zone) => String(zone.id) === String(zoneId));
    const source = current?.filters || {};
    const result = {
      zone_id: { title: '分区', min: 0, max: 1, default: zoneId, options: zoneOptions },
    };
    const groups = [
      ['category', 'categories', '题材'],
      ['area', 'areas', '地区'],
      ['language', 'languages', '语言'],
      ['year', 'years', '年份'],
      ['state', 'states', '状态'],
    ];
    for (const [key, plural, title] of groups) {
      const values = source[key] ?? source[plural] ?? [];
      if (!Array.isArray(values) || values.length === 0) continue;
      result[key] = {
        title, min: 0, max: 1, default: selected[key]?.[0] || '',
        options: Object.fromEntries(values.map((value) => [String(value), String(value)])),
      };
    }
    result.order_by = {
      title: '排序', min: 0, max: 1, default: selected.order_by?.[0] || 'update_time',
      options: { update_time: '更新时间', hits: '热度', score: '评分' },
    };
    return result;
  }

  async videos(page, filter = {}) {
    const data = await this.api('/videos', {
      page,
      page_size: PAGE_SIZE,
      zone_id: filter.zone_id?.[0] || '1',
      tag: filter.category?.[0] || '',
      area: filter.area?.[0] || '',
      language: filter.language?.[0] || '',
      year: filter.year?.[0] || '',
      order_by: filter.order_by?.[0] || 'update_time',
    });
    const items = Array.isArray(data) ? data : data?.items ?? data?.videos ?? data?.list ?? [];
    return items.map((video) => ({
      title: video.title || video.name || '',
      url: `/detail/${video.id ?? video.video_id}`,
      cover: video.cover_url || video.cover || video.poster || video.image || '',
      update: video.remarks || video.latest_episode || video.state || '',
    })).filter((item) => item.title && !item.url.endsWith('/undefined'));
  }

  async latest(page) {
    return this.videos(page);
  }

  async search(keyword, page, filter = {}) {
    const data = await this.api('/videos/search', {
      q: keyword,
      zone_id: filter.zone_id?.[0] || '1',
      page,
      page_size: PAGE_SIZE,
    });
    const items = Array.isArray(data) ? data : data?.items ?? data?.videos ?? data?.list ?? [];
    return items.map((video) => ({
      title: video.title || video.name || '',
      url: `/detail/${video.id ?? video.video_id}`,
      cover: video.cover_url || video.cover || video.poster || video.image || '',
      update: video.remarks || video.latest_episode || video.state || '',
    })).filter((item) => item.title && !item.url.endsWith('/undefined'));
  }

  async detail(url) {
    const id = String(url).split('/').filter(Boolean).pop();
    const video = await this.api(`/videos/${encodeURIComponent(id)}`);
    const sources = Array.isArray(video?.play_from) ? video.play_from : [];
    const urls = [];
    for (const source of sources) {
      if (!source?.code) continue;
      const data = await this.api(`/videos/${encodeURIComponent(id)}/sections`, {
        player_code: source.code,
        page: 1,
        page_size: 100,
      });
      const episodes = Array.isArray(data) ? data : data?.items ?? data?.sections ?? [];
      for (const episode of episodes) {
        if (episode?.id == null) continue;
        urls.push({
          name: episode.title || `第 ${episode.order || urls.length + 1} 话`,
          url: `/play/${id}/${episode.id}/${encodeURIComponent(source.code)}`,
        });
      }
    }
    return {
      title: video?.title || '次元城动画',
      cover: video?.cover_url || undefined,
      desc: video?.description || undefined,
      episodes: urls.length ? [{ title: '正片', urls }] : [],
    };
  }

  async watch(url) {
    const parts = String(url).split('/').filter(Boolean);
    const sectionId = parts[2];
    if (!sectionId) throw new Error('章节信息缺失，请重新打开番剧详情。');
    const response = await this.request(`/api/v2/sections/${encodeURIComponent(sectionId)}/play-url?expected_session_scope=video`, {
      headers: {
        'X-App-Name': 'cyc_web',
        'X-App-Version': 'cycweb',
        'X-Time-Zone': 'Asia/Shanghai',
        Referer: `${BASE_URL}/`,
        Accept: 'application/json',
      },
    });
    const data = typeof response === 'string' ? JSON.parse(response) : response;
    if (data?.code !== 0 || !data?.data?.url) {
      throw new Error(data?.msg || '请先登录次元城动画后再播放。');
    }
    const playUrl = data.data.url;
    return {
      type: /\.m3u8(?:\?|$)/i.test(playUrl) ? 'hls' : 'mp4',
      url: playUrl,
      headers: { Referer: `${BASE_URL}/` },
    };
  }

  isLoginSupported() {
    return true;
  }

  login() {
    return { mode: 'webview', url: `${BASE_URL}/login` };
  }


}
