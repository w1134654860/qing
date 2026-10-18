import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../app_ui.dart';
import '../app_interactions.dart';
import 'app_updates.dart';

class ReleaseSection {
  const ReleaseSection(this.title, this.items);
  final String title;
  final List<String> items;
}

const currentReleaseSummary = [
  '阅读器与听书升级：五种翻页效果、四边页边距与 0.5～3 倍速。',
  '扩展导入、扫描、分类与批量整理，支持自定义字体和繁体中文。',
  '统一阅读工具与入口，小说仅保留离线缓存；修复选字与插图，更新自动优先镜像。',
];

const currentReleaseSections = [
  ReleaseSection('阅读器与翻页', [
    '新增段落接续、无动画、平移、覆盖、纸页翻动五种效果，默认保持段落接续。横排与竖排均左右翻页；轻扫即可翻页，小幅拖动可回到原页。',
    '手动滚动或翻页到章节边界时自动衔接上下章，预先准备相邻正文；调整排版、恢复位置和拖动进度不会自行换章。',
    '新增点书直接阅读，未读书籍从首章开始，已读书籍直接续读。底部始终保留目录，进入详情页放在阅读器右上角。',
    '系统侧边返回第一次显示「再滑动一次退出阅读」，两秒内再次返回即可退出，不再弹确认框；顶部返回仍直接退出。',
    '四边页边距可分别调整，用「左右／左／右／上／下」选择对应边，共用滑块。字号、行距、边距与段落间距均支持透明实时预览。',
    '章内进度可透明拖动预览并提供轻刻度反馈。修复两端对齐与首行缩进同时开启时缩进失效，跨页续段不重复缩进。',
    '首次进入默认隐藏控件，之后记忆显示状态；加载阶段不闪出顶部工具栏。收放控件、横排与竖排切换保留位置，以逐段／逐列过渡衔接。',
    '隐藏系统状态栏后，时间与电量位于原状态栏区域，章节和页码在下方另成一行。滚动模式取消底部固定留白和模糊，顶部范围更紧凑。',
  ]),
  ReleaseSection('界面与操作调整', [
    '阅读设置、书签和听书合并为右上角一个阅读设置入口，分为「排版／操作／书签／听书」。',
    '本章进度、回到章首、跳至章末和章内查找移到底部目录；移除「返回原位」入口。',
    '阅读方式、翻页效果和阅读配色使用可直接点选的按钮；阅读字体进入带实际字形预览的页面，缩小选项占用空间。',
    '长按正文优先选中完整句子，可拖动选区扩大或缩小范围。菜单统一为「复制／书签／插图」，恢复横排和竖排的选区手柄。',
    '批量整理在「本地」分类与筛选栏右侧的圆圈勾选图标；合并书架后位于「书架」的同一位置，单本书整理菜单也可进入。',
    '详情页顶部「离线缓存」统一管理章节缓存、继续、取消和清除；本地书籍顶部保留配置入口。',
    '「本版更新」只在「我的 → 关于」展示，首页不再重复放卡片；先看摘要，再打开详细分页。',
  ]),
  ReleaseSection('插图与封面', [
    '长按正文点「插图」可查看本卷的独立插图章节和正文图片，支持缩略图、大图翻看、缩放及原图保存；缺少分卷信息时整理全书插图。',
    '修复第一根手指轻微滑动后第二根手指无法加入缩放；保留双指平移缩放、双击缩放、单击关闭和单指翻图。',
    '图片使用全屏画布，初始稍微缩小居中，顶部控件浮在图片上。移除图书列表的封面长按弹出预览，封面从详情页查看。',
    '修复关闭动效后插图闪现即消失的问题；修复部分 EPUB 阅读后封面丢失，保留小注释图片的原有尺寸。',
    '正文自带图片标记时按原位置显示；存在同版本本地 EPUB 时，通过图片前后唯一正文匹配补回位置。没有线索时保留插图章节，不按编号猜测位置；不再提供手动排版入口。',
  ]),
  ReleaseSection('本地导入与整理', [
    '支持 TXT、EPUB、MOBI／AZW／AZW3／PRC、FB2、PDF、DOCX、RTF、HTML、Markdown 与 ZIP 批量导入，继续沿用分卷合并和统一确认。',
    'EPUB／PDF／DOCX／ZIP 上限 512 MiB，Kindle 256 MiB，TXT／FB2／RTF 128 MiB，HTML／Markdown 32 MiB；ZIP 展开合计最多 1 GiB、200 本。加密／DRM 与暂不支持的 PDF 编码会明确提示。',
    '支持全部可访问共享存储或指定文件夹扫描。扫描前选格式，扫描后按格式、文件名或文件夹筛选，勾选确认后才导入；自动扫描只发现候选文件，不自动导入。',
    '导入与目录选择可使用兼容的文件应用。失败结果改为独立卡片；大书后台分块解码、逐章落盘，一本失败不影响其他书籍。',
    '本地与合并书架支持批量搜索、多选、全选当前结果并移除。可仅移出书架，或删除 App 管理的本机副本；保留外部原文件、进度与书签。',
    '修复立体书架＋列表漏书、部分封面丢失和旧版记录目录识别；用明确的空目录、访问与格式提示替代笼统网络异常。',
  ]),
  ReleaseSection('书架、发现与账号', [
    '新增合并书架，统一展示收藏、已缓存正文和本地书，来源角标区分在线／缓存／本地。开启后隐藏底部本地，导入位于书架右上角 ＋；关闭后恢复分开展示。',
    '合并状态联动离线适配、阅读器模式、搜索和来源筛选。书架与本地共用自定义分类，分类、数量、显示与筛选集中在同一行，排序收进筛选区域。',
    '发现支持多标签同时筛选，留在原来的立体书架与列表；清空和应用移到顶部，标签书单可继续加载，不再只显示前 20 本。',
    '搜索可指定书名、作者、标签或书号。修复作者／标签书单无法打开图书，复用重复作品页面并限制浏览嵌套层数。',
    '出版分类复用现有账号会话，登录返回与恢复时等待会话就绪，丢弃登录前失败请求，不再单独验证密码。登录表单接入系统自动填充与保存提示。',
    '账号卡使用文库头像，并接入登录后联网收藏自动同步；本地书籍和正文缓存不随取消收藏删除。',
  ]),
  ReleaseSection('我的、字体与语言', [
    '底部设置改为「我的」，集中账号、书签、设置与关于；设置按使用方式、阅读与外观、性能与动效、数据与存储进入独立二级页面。',
    '全局书签与阅读器共用记录，摘录可导出图片并选择图标水印，调整摘录字号与卡片排版。',
    '支持导入 TTF／OTF 字体，App 与阅读器可分别选择，阅读器也可跟随 App；选择项显示实际字形，切换阅读字体保留段落位置。',
    '支持简体中文、香港繁体、台湾繁体和跟随系统；语言与外观统一使用下拉菜单。',
    '统一搜索框、选择按钮和选中状态，移除勾选按钮多余留白。Toast 更短、更中性，位置随阅读控件收放移动，避开 Dock。',
  ]),
  ReleaseSection('听书与离线缓存', [
    '语速滑块、播放逻辑和保存设置统一支持 0.5～3 倍速，每格 0.05 倍，跨段与暂停后继续保留。',
    '保留双击当前段落暂停／继续、双击其他段落切换朗读位置；优化段落交接、播放进度与高亮，暂停跟随后可通过「开启跟随」回到朗读位置。',
    '关闭小说 EPUB／TXT 文件下载和导出，仅保留 App 内章节缓存；支持全部章节、后续 20 章、取消及失败续缓存。',
    '本地导入、原书同步、书签图片分享和插图保存保持原有用法；App 更新包仍可正常下载、校验与安装。',
  ]),
  ReleaseSection('性能与体验', [
    '发现、书架和本地惯性滚动复用已挂载条目，减少整帧重复重建和轻微抽动。',
    '深阅读位置恢复优先布局目标段落附近，非当前必需的预加载避开进场与位置恢复，减少详情进入滚动阅读器时的停顿。',
    '复用玻璃采样输入、稳定参数、排版与字形缓存，保留现有效果；时间、电量不重建正文，本卷插图后台最多整理两个章节。',
    '新增帧率偏好，可选择自动高刷、系统调度或设备支持的档位。屏幕刷新率不等于 App 实测帧率，省电和温控仍由系统决定。',
    '修复覆盖翻页阴影、选字命中偏移，以及控件收放时正文上下或竖排列边缘闪烁。',
  ]),
  ReleaseSection('版本说明与更新', [
    '新版本首次进入优先展示详细说明，使用「上一页／下一页」，最后一页为「完成」；完成后同一安装版本不再自动展示，随时可从「我的 → 关于」重看。',
    '更新检测、APK 下载、项目介绍与下载入口自动优先使用文库镜像，限流、超时或连接失败后自动直连 GitHub，不显示来源切换按钮。',
    '继续核对安装包真实版本、构建号、签名和完整性；不同来源的未完成文件不会拼接，取消和校验失败不会绕过验证。',
    '镜像只服务固定仓库，增加缓存与限流；封面和插图仍以原地址为主，仅在失败时使用独立备用通道。',
  ]),
];

class CurrentReleaseCard extends StatelessWidget {
  const CurrentReleaseCard({super.key, this.updates});
  final AppUpdates? updates;
  @override
  Widget build(BuildContext context) {
    final service = updates;
    Widget card() => ContentPanel(
      key: const ValueKey('current-release-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ArchiveSection(
            title: '本版更新',
            code:
                'RELEASE / ${service?.installed?.version ?? currentAppVersion}',
          ),
          const SizedBox(height: 12),
          for (final item in currentReleaseSummary)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: AppText(
                '· $item',
                style: const TextStyle(fontSize: 13, height: 1.6),
              ),
            ),
          const SizedBox(height: 6),
          GlassTextButton(
            key: const ValueKey('view-current-release-details'),
            onPressed: () =>
                showInstalledReleaseNotes(context, updates: service),
            child: const AppText('查看详细更新说明'),
          ),
        ],
      ),
    );
    return service == null
        ? card()
        : AnimatedBuilder(animation: service, builder: (_, _) => card());
  }
}

Future<bool> showInstalledReleaseNotes(
  BuildContext context, {
  AppUpdates? updates,
  bool automatic = false,
}) async {
  if (updates != null && updates.installed == null) {
    try {
      await updates.loadInstalled();
    } catch (_) {
      // Manual viewing remains available when platform metadata is unavailable.
    }
    if (!context.mounted) return false;
  }
  final installed = updates?.installed;
  final appearance = GlassAppearance.of(context);
  final reduced = MediaQuery.disableAnimationsOf(context);
  final completed =
      await showGeneralDialog<bool>(
        context: context,
        barrierDismissible: !automatic,
        barrierLabel: '关闭更新说明',
        barrierColor: Colors.black.withValues(alpha: .16),
        transitionDuration: reduced ? Duration.zero : NovelMotion.enter,
        transitionBuilder: (context, animation, secondary, child) =>
            GlassOverlayTransition(
              animation: animation,
              kind: GlassOverlayKind.sheet,
              reduceMotion: reduced,
              child: child,
            ),
        pageBuilder: (context, _, _) => GlassAppearance(
          blur: appearance.blur,
          opacity: appearance.opacity,
          child: PopScope(
            canPop: !automatic,
            child: _ReleaseDetails(
              version: installed?.version ?? currentAppVersion,
              build: installed?.build ?? currentAppBuild,
            ),
          ),
        ),
      ) ==
      true;
  if (completed && installed != null && updates != null) {
    try {
      await updates.rememberReleaseNotes(installed);
    } catch (_) {
      if (context.mounted) showNovelFeedback(context, '阅读状态未保存，下次打开可能再次显示');
    }
  }
  return completed;
}

class _ReleaseDetails extends StatefulWidget {
  const _ReleaseDetails({required this.version, required this.build});
  final String version;
  final int build;
  @override
  State<_ReleaseDetails> createState() => _ReleaseDetailsState();
}

class _ReleaseDetailsState extends State<_ReleaseDetails> {
  final _pages = PageController();
  final _sections = currentReleaseSections
      .where((s) => s.items.isNotEmpty)
      .toList(growable: false);
  int _page = 0;
  bool _moving = false;
  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _move(int page) async {
    if (_moving) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(page);
    } else {
      setState(() => _moving = true);
      await _pages.animateToPage(
        page,
        duration: NovelMotion.enter,
        curve: NovelMotion.ease,
      );
      if (mounted) setState(() => _moving = false);
    }
  }

  Widget _navigation(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final previous = GlassTextButton(
        key: const ValueKey('release-details-previous'),
        onPressed: _page == 0 || _moving ? null : () => _move(_page - 1),
        child: const AppText('上一页'),
      );
      final next = GlassPillButton(
        key: const ValueKey('release-details-next'),
        label: _page == _sections.length - 1 ? '完成' : '下一页',
        icon: _page == _sections.length - 1
            ? CupertinoIcons.checkmark
            : CupertinoIcons.arrow_right,
        onPressed: _moving
            ? null
            : () {
                if (_page == _sections.length - 1) {
                  Navigator.pop(context, true);
                } else {
                  _move(_page + 1);
                }
              },
      );
      if (constraints.maxWidth <
          MediaQuery.textScalerOf(context).scale(14) * 8 + 120) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [previous, const SizedBox(height: 6), next],
        );
      }
      return Row(
        children: [
          Expanded(child: previous),
          const SizedBox(width: 12),
          Expanded(child: next),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
            child: GlassOverlaySurface(
              key: const ValueKey('installed-release-details'),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ArchiveCode(
                      'RELEASE / ${widget.version} · ${widget.build}',
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Expanded(
                          child: AppText(
                            '本版更新',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        AppText(
                          '${_page + 1}/${_sections.length}',
                          key: const ValueKey('release-details-progress'),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: PageView.builder(
                        key: const ValueKey('release-details-pages'),
                        controller: _pages,
                        itemCount: _sections.length,
                        onPageChanged: (page) => setState(() => _page = page),
                        itemBuilder: (context, index) => SingleChildScrollView(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AppText(
                                _sections[index].title,
                                key: ValueKey('release-section-$index'),
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 14),
                              for (final item in _sections[index].items)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: AppText(
                                    '· $item',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      height: 1.75,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _navigation(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
