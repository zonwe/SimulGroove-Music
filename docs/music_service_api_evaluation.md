# 音乐服务 API 调研与 Flutter Music 接入评估

> 调研日期：2026-07-31  
> 目标项目：Flutter Music（Android、Windows、Web）  
> 结论基于各服务在调研日期公开的官方文档；价格、额度、开放范围和条款都可能变化，正式上线前必须重新确认。本文是工程评估，不是法律意见。

## 1. 结论先行

市面上基本不存在同时满足以下条件的服务：免费、主流商业曲库、可在第三方播放器中播放完整歌曲、可返回完整同步歌词、允许公开发布。

原因不是技术，而是录音版权、词曲版权和平台分发权是不同的授权。Spotify、Apple Music、TIDAL、YouTube 等即使开放 API，通常也只允许通过其官方 SDK/播放器播放，不会把可长期使用的裸音频 URL 和完整歌词交给第三方应用。

对本项目最现实的选择是：

1. **私人云音乐主线：OpenSubsonic + Navidrome。** 免费开源，能搜索和播放用户自己的完整曲库，也有封面、同步歌词、歌单、收藏、评分、播放记录和转码。它与本项目“私人本地音乐播放器”的定位最一致。
2. **免费在线曲库主线：Audius。** 免费额度大，可搜索并直接播放平台允许通过 API 分发的完整歌曲；但不是 Spotify 等主流商业曲库，也不提供歌词，应与 LRCLIB 组合。
3. **开放授权音乐补充：Jamendo。** 可直接取得独立音乐的播放 URL、授权信息、搜索、Radio 和部分歌词；免费方案面向非商业应用，目录和华语覆盖有限。
4. **歌词：LRCLIB。** 无需密钥，返回普通歌词和 LRC 同步歌词，与当前数据库字段和 LRC 解析器几乎直接兼容。适合个人版和原型；公开商业发行前仍需单独审查歌词内容的再分发权。
5. **网络电台：Radio Browser。** 免费且接入简单，适合补充“电台”功能，但不是按需点歌，也基本没有可靠歌词。
6. **听歌识曲：AudD。** 300 次免费试用后按量付费，REST 接口简单。面向国内、特别是哼唱识别时也可评估讯飞；不能把 API 密钥放进 Flutter 客户端。
7. **不建议作为第一阶段：Spotify、Apple Music、TIDAL、YouTube、酷狗。** 它们需要订阅、平台 SDK、商务授权或付费，且会破坏当前单一 `MusicAudioHandler + just_audio` 的播放架构。
8. **不要使用网易云、QQ 音乐、酷狗等逆向接口项目。** 这类接口通常依赖 Cookie、私有接口或伪造请求头，随时会失效，也没有第三方播放和歌词再分发授权。

## 2. 评估口径

### 2.1 “能够听歌”的三种含义

| 级别 | 含义 | 能否接入当前 `just_audio` |
| --- | --- | --- |
| A：直接音频流 | API 返回 MP3/AAC/HLS 等可播放地址，允许第三方播放器使用 | 最容易 |
| B：官方 SDK 播放 | 音频由服务商 SDK、DRM 或官方 App 播放 | 需要新增第二套播放后端 |
| C：试听/跳转 | 只有 30 秒预览，或只能跳到官方 App/网页 | 不能算完整在线听歌 |

本文只有 A 级被视为“可复用现有播放器播放完整歌曲”。

### 2.2 难度标尺

估时按一名熟悉本仓库的开发者计算，包含基础错误处理、单元测试，以及 Android、Windows、Web 的冒烟验证，不包含服务商合同审批和应用商店审核。

| 难度 | 参考工作量 | 典型情况 |
| --- | --- | --- |
| 低 | 1～3 人日 | 无登录的 JSON API，直接音频 URL 或歌词文本 |
| 中 | 4～10 人日 | OAuth/Token、分页、缓存、远程队列、限流和跨平台验证 |
| 高 | 2～6 周 | 原生 SDK、DRM、多个播放引擎、后端签名、商务审核或平台缺口 |

## 3. 最值得接入的免费或低成本服务

### 3.1 总表

| 服务 | 完整播放 | 歌词 | 常见能力 | 免费条件/限制 | 本项目难度 | 建议 |
| --- | --- | --- | --- | --- | --- | --- |
| [OpenSubsonic](https://opensubsonic.netlify.app/docs/opensubsonic-api/) + [Navidrome](https://www.navidrome.org/docs/overview/) | 是，用户自有曲库 | 是，含同步歌词扩展 | 搜索、艺人/专辑、封面、歌单、收藏、评分、相似歌曲、Radio、转码、播放队列、scrobble | 协议与 Navidrome 均开源免费；用户自行部署并拥有音乐 | 中，7～12 人日 | **私人云音乐首选** |
| [Audius](https://api.audius.co/plans) | 是，公开或满足 gate 条件的曲目 | 无官方歌词接口 | 搜索、Trending、用户、歌单、收藏、转发、评论、下载权限 | 免费 10 请求/秒、50 万请求/月；遵守曲目访问条件与 API 条款 | 中，5～8 人日 | **免费在线曲库首选** |
| [Jamendo](https://developer.jamendo.com/v3.0/docs) | 是，独立音乐 | 部分曲目有歌词 | 搜索、标签、相似艺人、Radio、歌单、收藏、授权信息 | 非商业应用公开方案最多 3.5 万请求/月；商业用途和具体曲目许可需复核 | 中，5～8 人日 | 开放授权音乐补充 |
| [LRCLIB](https://lrclib.net/docs) | 否 | 普通歌词 + LRC 同步歌词 | 精确匹配、搜索、投稿 | 无密钥、开放访问；必须标识客户端、顺序请求并遵守 `429/Retry-After` | 低，2～4 人日 | **歌词原型首选** |
| [Radio Browser](https://docs.radio-browser.info/) | 是，直播电台 | 否 | 按国家、语言、标签、Codec 搜索，返回解析后的流 URL | 免费社区服务，无账号；电台有效性和可用地区不受保证 | 低，2～3 人日 | 适合新增“网络电台” |
| [MusicBrainz](https://musicbrainz.org/doc/MusicBrainz_API) + [Cover Art Archive](https://musicbrainz.org/doc/Cover_Art_Archive/API) | 否 | 否 | 规范化元数据、MBID、ISRC、发行信息、封面 | 非商业 Web Service 免费；每 IP 平均不超过 1 请求/秒，并设置可联系的 User-Agent | 低～中，3～6 人日 | 本地曲库元数据增强 |
| [ListenBrainz](https://listenbrainz.readthedocs.io/en/latest/users/api/index.html) | 否 | 否 | 播放记录、Now Playing、统计、推荐、推荐反馈、歌单 | 用户 Token；动态限流，按响应头处理 | 中，4～7 人日 | 免费推荐/scrobble 可选 |
| [Last.fm](https://www.last.fm/api) | 否 | 否 | scrobble、相似歌曲/艺人、标签、热度、资料 | 非商业用途无偿；要求署名，商业使用需联系；条款明确不授予音乐流媒体权 | 中，4～7 人日 | ListenBrainz 的替代项 |
| [AcoustID](https://acoustid.org/webservice) | 否 | 否 | Chromaprint 指纹识别、映射 MusicBrainz | 仅非商业免费；更适合识别已有完整音频文件 | 中，4～8 人日 | 扫描后校正元数据，不适合作为首选“听歌识曲” |

### 3.2 OpenSubsonic / Navidrome

OpenSubsonic 是 Subsonic 音乐服务器协议的开放延续。它提供 `search3`、`stream`、`getCoverArt`、`getLyricsBySongId`、歌单、收藏、评分、播放队列和 scrobble 等接口。`stream` 直接返回音频二进制，并支持码率和转码格式参数；歌词扩展支持同步歌词、多语言和按歌曲 ID 获取。Navidrome 是成熟的免费服务端实现，兼容 Subsonic API 1.16.1 并逐步实现 OpenSubsonic 扩展。

优点：

- 完整播放、歌词、封面和歌单来自同一个服务，不需要跨服务匹配。
- 用户自行提供音乐，不需要购买商业平台的全曲库转授权。
- API 是普通 HTTP/JSON/XML；流地址能进入当前 `just_audio`。
- Android、Windows、Web 使用同一协议，平台差异小。
- Navidrome 支持转码，可解决 Web 和不同设备的 Codec 差异。

限制：

- 这不是公共曲库；每位用户必须有可访问的 Navidrome/OpenSubsonic 服务器。
- 认证兼容性需按服务端协商。不要把明文密码长期保存在 URL、日志或 Drift 普通设置中。
- Web 端需要服务端正确配置 HTTPS 和 CORS。
- 不同服务端对 OpenSubsonic 扩展的支持并不完全一致，必须先调用 `getOpenSubsonicExtensions` 做能力检测。

对本项目有两种路线：

1. **直接支持任意 OpenSubsonic 服务器，约 7～12 人日。** 用户填写服务器地址并登录，Flutter 端实现搜索、流播放、歌词和歌单。
2. **扩展现有 `backend/Music.Api`，约 2～4 周。** 当前后端已经能扫描服务器目录并列出曲目，但还没有音频 Range Streaming、时长/封面/歌词、统一曲库列表和客户端真实认证接入。若走这条路线，应新增账号隔离的流接口，绝不能把服务器绝对文件路径暴露给客户端。

推荐先实现通用 OpenSubsonic 客户端。它能更快验证产品形态，也避免立即复制一整套成熟音乐服务器能力。

### 3.3 Audius

Audius 的 REST API 可以搜索、获取 Trending、用户和歌单，并通过 `GET /tracks/{track_id}/stream` 取得可播放 MP3。官方免费方案为 10 请求/秒和 50 万请求/月。Audius 也明确允许艺人关闭 API Streaming，或者设置关注、付费、Token 等 gate，因此 UI 必须根据 `access.stream` 和 gate 条件决定是否展示播放按钮，不能假定每首歌都可播。

优点：

- 真正适合接入自定义播放器的免费完整流，不需要 Spotify Premium。
- `Track` 的稳定 ID、时长、封面和用户信息比较完整。
- 当前播放器已经能处理远程 URI，技术闭环较短。

限制：

- 曲库以独立艺人和 Audius 生态为主，不等价于 Spotify、QQ 音乐或网易云的主流曲库。
- 没有官方歌词 API，需要使用 LRCLIB 等第二来源匹配。
- 流可能被下架、改成 gated 或禁止第三方 API 播放，应在每次播放前重新解析可用性。
- API Bearer Token 不应作为真正秘密硬编码进公开客户端。原型可直连，生产版更适合由后端代理并做限流。

### 3.4 Jamendo

Jamendo 面向独立音乐，公开 API 目录约数十万首。`tracks` 返回可播放 `audio` 字段，可选择 MP3/Ogg/FLAC 格式；`include=lyrics+licenses+musicinfo` 可附带歌词、Creative Commons/商业许可和音乐信息。官方还提供搜索、标签、相似艺人、Radio 和 OAuth 用户收藏。

需要注意：

- 官方开发页把公开非商业方案标为最多 3.5 万请求/月；超过规模或商业化时应联系 Jamendo。
- 可播放不等于可下载，必须检查 `audiodownload_allowed`。
- 不同曲目许可证可能包含署名、非商业或禁止演绎等条件，结果页应保留作者、来源和许可链接。
- 歌词是可选字段，不能代替专门歌词服务。

### 3.5 LRCLIB

LRCLIB 的 `GET /api/get` 以歌曲名、艺人、专辑和时长做精确匹配，返回 `plainLyrics` 与 `syncedLyrics`；`GET /api/search` 可做模糊搜索。时长容差约为正负 2 秒，正好可以利用当前 `Tracks.durationMs`。

它与本项目非常匹配：

- `Tracks.lyrics` 已能保存字符串。
- `parseLrc` 和播放页已经能显示同步歌词。
- 扫描器已经优先读取内嵌歌词和同名 `.lrc`，在线歌词只需作为缺失时的 fallback。

推荐匹配顺序：本地内嵌/同名 LRC → LRCLIB 精确匹配 → LRCLIB 搜索并让用户选择 → 无歌词。不要用模糊匹配结果自动覆盖本地歌词。

工程上必须设置 `User-Agent`、`X-User-Agent` 或 `Lrclib-Client`，批量获取时串行并间隔 200～500 ms，缓存成功和短期失败结果，并尊重 `Retry-After`。

风险：LRCLIB 服务和服务器代码免费，并不自动证明每份用户贡献歌词都拥有面向商业应用的再分发授权。个人播放器/原型风险较低；计划公开商业发行时，应让法务确认或切换到有明确内容许可的歌词供应商。

### 3.6 Radio Browser

Radio Browser 返回 `url_resolved`，已经处理 M3U/PLS、HTTP 重定向等常见问题，可直接交给播放器。它还提供名称、国家、语言、标签、Codec、码率、主页和图标。

实现很轻，但产品上应放在独立“网络电台”页面：直播流没有可跳转队列、精确时长或稳定歌曲 ID，台站元数据也不保证提供当前曲名。不要把它混入普通歌曲列表和本地歌单同步逻辑。

## 4. 主流商业音乐平台

### 4.1 对比表

| 服务 | 官方播放方式 | 歌词 API | 费用/准入现状 | 跨本项目三平台 | 结论 |
| --- | --- | --- | --- | --- | --- |
| [Spotify](https://developer.spotify.com/documentation/) | Android/iOS App Remote 控制 Spotify App；Web Playback SDK 在浏览器内播放；Web API 控制 Connect 设备 | 无公开歌词正文接口 | 2026 Dev Mode 要求应用所有者保持 Premium，单应用最多 5 位用户；Web Playback 也要求 Premium，且流媒体集成有非商业限制 | Android 和 Web 各一套，Windows 原生没有等价 SDK；不能进入 `just_audio` | 高难度，不作为当前路线 |
| [Apple Music / MusicKit](https://developer.apple.com/musickit/) | Android 原生 SDK、Apple 平台 MusicKit、Web JS 播放 | 只暴露 `hasLyrics`，未提供歌词正文 | 开发者计划 99 美元/年；完整播放要求用户有 Apple Music 订阅 | Android/Web 可做，Windows 原生缺口明显 | 高难度，除非产品明确押注 Apple Music |
| [TIDAL](https://developer.tidal.com/reference) | 官方 Android、iOS、Web Player SDK；REST API 做目录与用户数据 | 不应假定有可再分发歌词正文 | 需注册应用；生产资格、订阅和可播放范围应在 Dashboard/条款中单独确认 | Android/Web 有 SDK，Windows 原生缺口 | 高难度，先做平台 PoC 再评估 |
| [SoundCloud](https://developers.soundcloud.com/docs/api/) | 对 `playable` 曲目可用自定义播放器流式播放，也可用 Widget | 无官方歌词正文 | 目前注册 API 应用要求 Artist Pro；播放请求 1.5 万次/24 小时；需要署名和来源链接 | 直接流理论上三端可用 | 中～高；不是免费首选，但比 Spotify 更适合自定义播放器 |
| [酷狗曲库开放组件](https://open.kugou.com/docs/open-player/) | Android/iOS 官方无界面播放 SDK | 公开页未证明提供完整歌词接口 | 按歌曲千次有效播放计费，要求“酷狗提供技术支持”标识并完成隐私披露 | 仅 Android/iOS，Windows/Web 无对应能力 | 中文正版曲库可商务评估，但与当前三端目标不匹配 |
| [YouTube Data API + IFrame Player](https://developers.google.com/youtube/terms/required-minimum-functionality) | 必须使用可见的官方嵌入播放器 | Caption 不是通用歌词；下载字幕需要 OAuth 和相应内容权限 | Data API 有免费配额，但禁止分离音频、隐藏播放器和后台播放 | WebView/嵌入播放器可做，不能复用音频队列 | 与音乐播放器核心体验和条款冲突，不建议 |
| [Deezer](https://en.deezercommunity.com/features-feedback-44/api-auth-impossible-80857) | 历史 API/SDK | 不作为可靠歌词来源 | 截至调研日仍不接受个人创建新的 API 应用；官方社区解释为滥用和版权协议问题 | 无法正常申请即没有工程意义 | 当前不可选 |
| [Amazon Music](https://developer.amazon.com/docs/music/landing_home.html) | Web Playback API + DRM | 未见适合本项目的公开歌词接口 | 仍是 closed beta | 不可自助接入 | 暂不评估实施 |
| [iTunes Search API](https://performance-partners.apple.com/resources/documentation/itunes-store-web-service-search-api/) | 30 秒预览 URL | 无 | 约 20 请求/分钟；官方条款要求预览仅用于推广并靠近商店徽章，不能作为独立娱乐 | 三端都易播放，但用途不允许当播放器 | 只可做商店搜索/跳转，不可作为听歌来源 |

### 4.2 为什么这些平台接入成本高

当前 `MusicAudioHandler` 是播放状态的唯一事实源，内部只有一个 `just_audio.AudioPlayer`。Spotify、Apple Music、TIDAL、酷狗和 YouTube 的播放发生在其 App、JavaScript Player、DRM SDK 或原生 SDK 中，不能简单包装成 `AudioSource.uri`。

若一定要支持，需要先把播放器重构成能力接口，例如：

```text
PlaybackCoordinator
├── DirectUrlPlaybackBackend      本地文件 / OpenSubsonic / Audius / Jamendo / Radio
├── SpotifyRemoteBackend          Android；Web 另有 JS 实现
├── AppleMusicPlaybackBackend     Android；Web 另有 JS 实现
└── ProviderSdkPlaybackBackend    TIDAL / 酷狗等
```

每个后端还要统一队列、进度、循环、随机、系统媒体通知、桌面快捷键、托盘、音量、锁屏和错误状态。对本项目而言，这不是“加一个 API”，而是一次播放器架构升级。

## 5. 歌词服务专项评估

| 服务 | 能否直接取歌词正文 | 同步歌词 | 授权/费用判断 | 建议 |
| --- | --- | --- | --- | --- |
| [LRCLIB](https://lrclib.net/docs) | 是 | 是，LRC | 免费、无密钥；内容再分发权仍需自行评估 | 个人版和原型首选 |
| OpenSubsonic/Navidrome | 是，来自用户自己的文件/标签 | 是 | 用户对自己的媒体负责 | 私人云曲库首选 |
| Jamendo | 部分曲目 | 文档只保证 lyrics 字段，不保证逐行同步 | 随曲目许可和 API 条款 | 仅用于 Jamendo 曲目 |
| [Musixmatch](https://www.postman.com/musixmatch-dev/musixmatch-apis/overview) | 是，授权歌词目录 | 供应能力较完整 | 官方开发入口要求选择 Plan；生产价格和展示限制应向官方确认，不能按永久免费设计 | 商业版候选 |
| [Genius](https://docs.genius.com/) | 官方 API 不直接返回可自由使用的完整歌词正文 | 否 | 常见库通过抓取网页取得歌词；不应把抓取当作官方 API 能力 | 不接入抓取方案 |
| Spotify / Apple Music | Spotify 无公开歌词正文；Apple Music 公开对象只有 `hasLyrics` | 不可供第三方自由取用 | 歌词展示权不随播放 API 自动授予 | 不作为歌词源 |

数据库中建议额外记录 `lyricsSource`、`lyricsRemoteId`、`lyricsFetchedAt` 和 `lyricsMatchConfidence`，避免未来不知道歌词来源，也便于更换供应商和处理用户手工修正。若暂时不改 schema，至少在 Repository 层保留来源，下一次数据库迁移再落盘。

## 6. 听歌识曲和其他常见能力

### 6.1 听歌识曲

| 服务 | 免费情况 | 适用场景 | 难度 | 备注 |
| --- | --- | --- | --- | --- |
| [AudD](https://www.audd.io/) | 注册送 300 次，之后 5 美元/1000 次起 | 录制约 12 秒环境音乐后识别 | 中，3～6 人日 | REST 简单、返回歌曲/艺人/专辑/ISRC 和平台链接；音频与密钥应经后端发送 |
| [讯飞歌曲识别](https://www.xfyun.cn/doc/voiceservice/song-recognition/API.html) | 旧版文档写明 500 次免费调用 | 目前该文档明确只开放哼唱识别，原声识别仍在优化 | 中，4～7 人日 | 不支持浏览器跨域，必须经过后端；适合中文哼唱场景 |
| [讯飞 ACRCloud 歌曲识别](https://www.xfyun.cn/doc/voiceservice/music_recognition/API.html) | 公开文档未给出可长期依赖的免费额度 | 原声与哼唱、中文曲库 | 中，4～7 人日 | HMAC 鉴权和音频预处理放后端；上线前询价 |
| [ShazamKit](https://developer.apple.com/shazamkit/) | 依赖 Apple Developer 能力和账号 | Shazam 曲库识别 | 高 | Android/Apple 有 SDK，Windows/Web 缺口，不符合“最好免费” |
| [AcoustID](https://acoustid.org/webservice) | 非商业免费 | 给已有本地文件生成 Chromaprint 后校正标签 | 中～高 | 更适合扫描文件，不适合短环境录音；Web 端原生指纹计算困难 |

本项目的 `recognition_page.dart` 仍是占位页，Android Manifest 中的麦克风权限也不能代表功能已实现。实施识曲还需要：显式用户授权、录音状态和倒计时、取消、音频重采样/压缩、上传进度、超时、无匹配、多个候选、隐私说明和临时音频删除。

### 6.2 元数据、封面、推荐和播放记录

- **MusicBrainz + Cover Art Archive：** 适合根据艺人、专辑、曲名、ISRC 或 AcoustID 补全规范名称、发行年份、MBID 和封面。必须限速和缓存，不能在列表滚动时逐行请求。
- **ListenBrainz：** 可以提交 `playing_now` 和完成播放记录，得到统计、推荐与推荐反馈。其官方规则建议歌曲播放一半或 4 分钟（取较短者）后才提交完整 listen，能直接挂在 `MusicAudioHandler` 的进度流上。
- **Last.fm：** 同样适合 scrobble、相似艺人和标签，但官方条款明确 API 不授予播放音乐的权利，非商业使用也要求署名。
- **Radio Browser：** 可提供直播电台发现，但推荐结果和普通歌曲推荐应分开展示。

## 7. 与当前仓库的适配分析

### 7.1 已有优势

- `Tracks` 已有 `remoteId`、`sourceType`、`sourceId`、`uri`、`artwork` 和 `lyrics`，第一版远程歌曲通常不需要立刻改表。
- 非 Windows 本地文件会直接把 `Track.uri` 交给 `AudioSource.uri`；Windows 也只对 `windows_file` 做特殊处理，因此普通 HTTPS 音频已有基本播放通路。
- `MusicAudioHandler` 已统一队列、进度、媒体通知、循环和随机模式，直接 URL 服务可以复用。
- LRC 解析与歌词 UI 已完成，在线歌词只缺 Repository、匹配、缓存和交互。
- Riverpod 已有全局 Provider 集中入口，适合注入网络客户端和服务 Repository。
- 实验性 ASP.NET 后端可以保护服务密钥、签发短期 URL、代理 CORS、做限流和识曲音频上传。

### 7.2 当前缺口

- `pubspec.yaml` 已启用 `http`，账号、同步与服务器扫描复用现有 HTTP 边界；在线音乐服务仍需独立 Repository 和契约。
- 在线搜索页仍是占位页，没有网络状态、分页、服务选择、错误恢复或结果模型。
- `BackendGateway` 已由 `HttpBackendGateway` 提供，真实登录、Refresh Token 轮换和安全存储已接入主 UI。
- `MusicAudioHandler.playTracks` 只接收 Drift `Track`，没有“播放时解析短期流 URL/请求头”的抽象。
- 当前 `Track.uri` 有唯一约束；短期签名 URL 不能作为远程歌曲的稳定身份，也不应长期落库。
- 后端扫描结果只有文件路径和基础标签，尚无账号隔离的音频流、HTTP Range、封面、歌词和时长接口。
- Web 需要逐个验证服务端 CORS、重定向、Range、Content-Type 和混合内容限制。

## 8. 推荐的实现架构

### 8.1 目录与接口

建议新增独立边界，不把某个供应商的 JSON 直接传进 Widget：

```text
lib/core/online_music/
├── online_music_service.dart
├── online_catalog_track.dart
├── resolved_audio_source.dart
├── online_music_repository.dart
├── lyrics_repository.dart
└── providers/
    ├── audius_service.dart
    ├── opensubsonic_service.dart
    ├── jamendo_service.dart
    └── lrclib_service.dart
```

核心能力可设计为：

```dart
abstract interface class OnlineMusicService {
  Set<OnlineMusicCapability> get capabilities;
  Future<OnlineSearchPage> search(String query, {String? cursor});
  Future<ResolvedAudioSource> resolveStream(String trackId);
  Future<String?> getLyrics(String trackId);
}
```

`ResolvedAudioSource` 至少包含 `uri`、可选请求头和 `expiresAt`。数据库只保存 `provider + remoteTrackId` 作为稳定身份；每次播放前解析可能过期的真实流地址。

### 8.2 安全边界

- 客户端可以保存可公开的 Client ID，但 Client Secret、Apple 私钥、SoundCloud Secret、识曲 API Secret 必须留在后端。
- 用户 Refresh Token 不应明文放入 `AppSettings`。Android/Windows 使用安全存储；Web 优先采用后端 HttpOnly Session/Cookie 或短期 Token。
- 后端代理接口应按账号限流，不记录歌词正文、Token、原始识曲音频或带凭据的完整 URL。
- 远程流重定向必须限制允许的域名，避免把后端做成任意 URL 代理。
- 服务端曲库流必须支持 `Range`/`206 Partial Content`，并在读取文件前再次检查账号和规范化路径。

### 8.3 UI 与能力降级

- 搜索结果按来源显示标识，并明确“完整歌曲”“试听”“电台直播”。
- 服务不支持歌词、收藏或下载时隐藏对应操作，不显示必然失败的按钮。
- 远程流失效时先重新解析一次，再显示可理解的错误；不要无限重试。
- 在线结果不要自动混进“本地音乐库”。可以允许用户收藏远程引用，但应在离线时显示不可用。
- 同名歌曲匹配歌词时显示来源和候选，避免现场版、翻唱版、加速版套用错误歌词。

## 9. 分阶段落地计划

### 阶段 0：技术尖峰，1～2 人日

1. 用 `just_audio` 分别在 Android、Windows、Web 播放一个 Audius 或 Jamendo 的 HTTPS 流。
2. 验证暂停、Seek、切歌、后台媒体通知、重定向和 Web CORS。
3. 用一首已有时长的本地曲目调用 LRCLIB，并把返回的 `syncedLyrics` 送入现有 `parseLrc`。

只有三端尖峰通过后再建设通用抽象。

### 阶段 1：在线歌词，2～4 人日

实现 `LyricsRepository`、LRCLIB 精确匹配、手动候选、缓存、限流和错误状态。这是投入最小、能立即提升现有本地音乐体验的功能。

### 阶段 2A：私人云音乐，7～12 人日

实现 OpenSubsonic 登录、能力探测、`search3`、封面、`stream`、`getLyricsBySongId`、收藏和歌单。若产品仍以私人音乐为核心，优先做此阶段。

### 阶段 2B：免费在线曲库，5～8 人日

实现 Audius 搜索、Trending、详情、播放、可用性/gate 状态和来源署名；LRCLIB 只作歌词 fallback。若更重视发现陌生音乐，可先于 2A。

### 阶段 3：Jamendo 与网络电台，4～8 人日

增加 Jamendo 授权筛选/署名和 Radio Browser 独立页面。两者都通过能力接口接入，不扩散服务特有字段。

### 阶段 4：识曲与推荐，5～10 人日

识曲优先 AudD 后端代理，国内哼唱再试讯飞；推荐优先 ListenBrainz。应在真实登录和安全 Token 存储完成后上线账号相关能力。

## 10. 最终推荐组合

### 个人免费版

```text
本地音乐 / Navidrome(OpenSubsonic)  → 完整播放、封面、歌单、用户自有歌词
LRCLIB                              → 缺失同步歌词补全
MusicBrainz + Cover Art Archive     → 元数据与封面补全
ListenBrainz                        → 播放记录与推荐
Radio Browser                       → 网络电台
Audius                              → 免费在线独立音乐
```

这套组合几乎没有固定 API 成本，也最符合私人播放器定位。代价是主流商业歌曲仍须由用户自己的合法音乐文件或 Navidrome 曲库提供。

### 面向公众的商业版

不能仅靠免费 API 拼接。应先决定目标市场和核心曲库，再与酷狗、Apple Music、TIDAL、SoundCloud 或专业音乐/歌词授权商谈正式授权；同时把播放器重构成多后端架构。歌词应使用 Musixmatch 等有明确商业授权的供应商，而不是默认依赖社区歌词库。

## 11. 官方资料索引

- [OpenSubsonic API 方法总览](https://opensubsonic.netlify.app/docs/opensubsonic-api/)
- [OpenSubsonic stream](https://opensubsonic.netlify.app/docs/endpoints/stream/)
- [OpenSubsonic 同步歌词扩展](https://opensubsonic.netlify.app/docs/endpoints/getlyricsbysongid/)
- [Navidrome Subsonic 兼容性](https://www.navidrome.org/docs/developers/subsonic-api/)
- [Audius 免费额度](https://api.audius.co/plans)
- [Audius REST API / stream](https://api.audius.co/v1)
- [Audius API Streaming 控制说明](https://help.audius.co/product/editing-your-release)
- [Jamendo Tracks API](https://developer.jamendo.com/v3.0/tracks)
- [Jamendo 认证和额度说明](https://developer.jamendo.com/v3.0/authentication)
- [LRCLIB API 文档](https://lrclib.net/docs)
- [Radio Browser API](https://docs.radio-browser.info/)
- [MusicBrainz API 与免费条件](https://musicbrainz.org/doc/MusicBrainz_API)
- [ListenBrainz API](https://listenbrainz.readthedocs.io/en/latest/users/api/index.html)
- [Last.fm API 条款](https://www.last.fm/api/tos)
- [Spotify 2026 Dev Mode 变化](https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide)
- [Spotify Web Playback SDK](https://developer.spotify.com/documentation/web-playback-sdk/reference)
- [Apple Music MusicKit](https://developer.apple.com/musickit/)
- [Apple Developer Program 费用](https://developer.apple.com/support/compare-memberships/)
- [SoundCloud API Guide](https://developers.soundcloud.com/docs/api/)
- [SoundCloud API 应用注册条件](https://developers.soundcloud.com/docs/api/register-app)
- [SoundCloud Rate Limits](https://developers.soundcloud.com/docs/api/rate-limits)
- [酷狗曲库开放组件](https://open.kugou.com/docs/open-player/)
- [YouTube API 播放政策](https://developers.google.com/youtube/terms/developer-policies-guide)
- [Amazon Music Developer closed beta](https://developer.amazon.com/docs/music/landing_home.html)
- [AudD API 与价格](https://www.audd.io/)
- [讯飞歌曲识别](https://www.xfyun.cn/doc/voiceservice/song-recognition/API.html)
