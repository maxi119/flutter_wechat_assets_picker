///
/// [Author] Alex (https://github.com/AlexV525)
/// [Date] 2020-10-31 00:15
///
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/constants.dart';

abstract class AssetPickerViewerBuilderDelegate<A, P> {
  AssetPickerViewerBuilderDelegate({
    @required this.provider,
    @required this.previewAssets,
    @required this.themeData,
    @required int currentIndex,
    this.selectedAssets,
    this.selectorProvider,
  }) {
    _currentIndex = currentIndex;
  }

  /// [ChangeNotifier] for photo selector viewer.
  /// 资源预览器的状态保持
  final AssetPickerViewerProvider<A> provider;

  /// Assets provided to preview.
  /// 提供预览的资源
  final List<A> previewAssets;

  /// Theme for the viewer.
  /// 主题
  final ThemeData themeData;

  /// Selected assets.
  /// 已选的资源
  final List<A> selectedAssets;

  /// Provider for [AssetPicker].
  /// 资源选择器的状态保持
  final AssetPickerProvider<A, P> selectorProvider;

  /// [StreamController] for viewing page index update.
  /// 用于更新当前正在浏览的资源页码的流控制器
  ///
  /// The main purpose is narrow down build parts when page index is changing,
  /// prevent widely [setState] and causing other widgets rebuild.
  /// 使用 [StreamController] 的主要目的是缩小页码变化时构建组件的范围，
  /// 防止滥用 [setState] 导致其他部件重新构建。
  final StreamController<int> pageStreamController =
      StreamController<int>.broadcast();

  /// The [State] for a viewer.
  /// 预览器的状态实例
  AssetPickerViewerState<A, P> viewerState;

  /// The [TickerProvider] for animations.
  /// 用于动画的 [TickerProvider]
  TickerProvider vsync;

  /// Current previewing index in assets.
  /// 当前查看的索引
  int _currentIndex;

  int get currentIndex => _currentIndex;

  set currentIndex(int value) {
    if (_currentIndex == value) {
      return;
    }
    _currentIndex = value;
  }

  /// Getter for the current asset.
  /// 当前资源的Getter
  A get currentAsset => previewAssets.elementAt(currentIndex);

  /// Height for bottom detail widget.
  /// 底部详情部件的高度
  double get bottomDetailHeight => 140.0;

  /// Whether the current platform is Apple OS.
  /// 当前平台是否为苹果系列系统
  bool get isAppleOS => Platform.isIOS || Platform.isMacOS;

  /// Call when viewer is calling [initState].
  /// 当预览器调用 [initState] 时注册 [State] 和 [TickerProvider]。
  void initStateAndTicker(AssetPickerViewerState<A, P> s, TickerProvider v) {
    viewerState = s;
    vsync = v;
  }

  /// Keep a dispose method to sync with [State].
  /// 保留一个 dispose 方法与 [State] 同步。
  void dispose();

  /// Split page builder according to type of asset.
  /// 根据资源类型使用不同的构建页
  Widget assetPageBuilder(BuildContext context, int index);

  /// Common image load state changed callback with [Widget].
  /// 图片加载状态的部件回调
  Widget previewWidgetLoadStateChanged(
    BuildContext context,
    ExtendedImageState state,
  ) {
    Widget loader;
    switch (state.extendedImageLoadState) {
      case LoadState.loading:
        loader = const SizedBox.shrink();
        break;
      case LoadState.completed:
        loader = FadeImageBuilder(child: state.completedWidget);
        break;
      case LoadState.failed:
        loader = failedItemBuilder(context);
        break;
    }
    return loader;
  }

  /// The item widget when [AssetEntity.thumbData] load failed.
  /// 资源缩略数据加载失败时使用的部件
  Widget failedItemBuilder(BuildContext context) {
    return Center(
      child: Text(
        Constants.textDelegate.loadFailed,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18.0),
      ),
    );
  }

  /// Confirm button.
  /// 确认按钮
  Widget confirmButton(BuildContext context);

  /// Select button.
  /// 选择按钮
  Widget selectButton(BuildContext context);

  /// Thumb item widgets in bottom detail.
  /// 底部信息栏单个资源缩略部件
  Widget bottomDetailItemBuilder(BuildContext context, int index);

  /// Detail widget aligned to bottom.
  /// 底部信息部件
  Widget bottomDetailBuilder(BuildContext context);

  /// Yes, the build method.
  /// 没错，是它是它就是它，我们亲爱的 build 方法~
  Widget build(BuildContext context);
}

class DefaultAssetPickerViewerBuilderDelegate
    extends AssetPickerViewerBuilderDelegate<AssetEntity, AssetPathEntity> {
  DefaultAssetPickerViewerBuilderDelegate({
    @required int currentIndex,
    @required List<AssetEntity> previewAssets,
    @required AssetPickerViewerProvider<AssetEntity> provider,
    @required ThemeData themeData,
    List<AssetEntity> selectedAssets,
    AssetPickerProvider<AssetEntity, AssetPathEntity> selectorProvider,
    this.previewThumbSize,
    this.specialPickerType,
    this.isPreviewOnly = true,
  }) : super(
          currentIndex: currentIndex,
          previewAssets: previewAssets,
          provider: provider,
          themeData: themeData,
          selectedAssets: selectedAssets,
          selectorProvider: selectorProvider,
        );

  /// Thumb size for the preview of images in the viewer.
  /// 预览时图片的缩略图大小
  final List<int> previewThumbSize;

  /// The current special picker type for the viewer.
  /// 当前特殊选择类型
  ///
  /// If the type is not null, the title of the viewer will not display.
  /// 如果类型不为空，则标题将不会显示。
  final SpecialPickerType specialPickerType;

  /// [AnimationController] for double tap animation.
  /// 双击缩放的动画控制器
  AnimationController _doubleTapAnimationController;

  /// [CurvedAnimation] for double tap.
  /// 双击缩放的动画曲线
  Animation<double> _doubleTapCurveAnimation;

  /// [Animation] for double tap.
  /// 双击缩放的动画
  Animation<double> _doubleTapAnimation;

  /// Callback for double tap.
  /// 双击缩放的回调
  VoidCallback _doubleTapListener;

  /// [PageController] for assets preview [PageView].
  /// 查看图片资源的页面控制器
  PageController pageController;

  /// Whether detail widgets displayed.
  /// 详情部件是否显示
  bool isDisplayingDetail = true;

  bool isPreviewOnly;

  @override
  void initStateAndTicker(
    AssetPickerViewerState<AssetEntity, AssetPathEntity> s,
    TickerProvider v,
  ) {
    super.initStateAndTicker(s, v);
    _doubleTapAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: v,
    );
    _doubleTapCurveAnimation = CurvedAnimation(
      parent: _doubleTapAnimationController,
      curve: Curves.easeInOut,
    );
    pageController = PageController(initialPage: currentIndex);
  }

  @override
  void dispose() {
    _doubleTapAnimationController?.dispose();
    pageStreamController?.close();
  }

  /// Execute scale animation when double tap.
  /// 双击时执行缩放动画
  void updateAnimation(ExtendedImageGestureState state) {
    final double begin = state.gestureDetails.totalScale;
    final double end = state.gestureDetails.totalScale == 1.0 ? 3.0 : 1.0;
    final Offset pointerDownPosition = state.pointerDownPosition;

    _doubleTapAnimation?.removeListener(_doubleTapListener);
    _doubleTapAnimationController
      ..stop()
      ..reset();
    _doubleTapListener = () {
      state.handleDoubleTap(
        scale: _doubleTapAnimation.value,
        doubleTapPosition: pointerDownPosition,
      );
    };
    _doubleTapAnimation = Tween<double>(
      begin: begin,
      end: end,
    ).animate(_doubleTapCurveAnimation)
      ..addListener(_doubleTapListener);

    _doubleTapAnimationController.forward();
  }

  /// Method to switch [isDisplayingDetail].
  /// 切换显示详情状态的方法
  void switchDisplayingDetail({bool value}) {
    isDisplayingDetail = value ?? !isDisplayingDetail;
    if (viewerState.mounted) {
      // ignore: invalid_use_of_protected_member
      viewerState.setState(() {});
    }
  }

  /// Sync selected assets currently with asset picker provider.
  /// 在预览中当前已选的图片同步到选择器的状态
  Future<bool> syncSelectedAssetsWhenPop() async {
    if (provider?.currentlySelectedAssets != null) {
      selectorProvider.selectedAssets = provider.currentlySelectedAssets;
    }
    return true;
  }

  @override
  Widget assetPageBuilder(BuildContext context, int index) {
    final AssetEntity asset = previewAssets.elementAt(index);
    Widget builder;
    switch (asset.type) {
      case AssetType.audio:
        builder = AudioPageBuilder(asset: asset, state: viewerState);
        break;
      case AssetType.image:
        builder = ImagePageBuilder(
          asset: asset,
          state: viewerState,
          previewThumbSize: previewThumbSize,
        );
        break;
      case AssetType.video:
        builder = VideoPageBuilder(asset: asset, state: viewerState);
        break;
      case AssetType.other:
        builder = Center(
          child: Text(Constants.textDelegate.unSupportedAssetType),
        );
        break;
    }
    return builder;
  }

  /// Preview item widgets for audios.
  /// 音频的底部预览部件
  Widget _audioPreviewItem(AssetEntity asset) {
    return ColoredBox(
      color: viewerState.context?.themeData?.dividerColor,
      child: const Center(child: Icon(Icons.audiotrack)),
    );
  }

  /// Preview item widgets for images.
  /// 音频的底部预览部件
  Widget _imagePreviewItem(AssetEntity asset) {
    return Positioned.fill(
      child: RepaintBoundary(
        child: ExtendedImage(
          image: AssetEntityImageProvider(
            asset,
            isOriginal: false,
          ),
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  /// Preview item widgets for video.
  /// 音频的底部预览部件
  Widget _videoPreviewItem(AssetEntity asset) {
    return Positioned.fill(
      child: Stack(
        children: <Widget>[
          _imagePreviewItem(asset),
          Center(
            child: Icon(
              Icons.video_library,
              color: themeData.colorScheme.surface.withOpacity(0.54),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget bottomDetailItemBuilder(BuildContext context, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
      child: AspectRatio(
        aspectRatio: 1.0,
        child: StreamBuilder<int>(
          initialData: currentIndex,
          stream: pageStreamController.stream,
          builder: (BuildContext _, AsyncSnapshot<int> snapshot) {
            final AssetEntity asset = selectedAssets.elementAt(index);
            final bool isViewing = asset == currentAsset;

            return GestureDetector(
              onTap: () {
                if (previewAssets == selectedAssets) {
                  // tap from preview, only selected in previewAssets
                  pageController.jumpToPage(index);
                } else {
                  // tap on backdrop, all assets in previewAssets
                  final pageIndex = previewAssets.indexOf(asset);
                  pageController.jumpToPage(pageIndex);
                }
              },
              child: Selector<AssetPickerViewerProvider<AssetEntity>,
                  List<AssetEntity>>(
                selector: (
                  BuildContext _,
                  AssetPickerViewerProvider<AssetEntity> provider,
                ) =>
                    provider.currentlySelectedAssets,
                builder: (
                  BuildContext _,
                  List<AssetEntity> currentlySelectedAssets,
                  Widget __,
                ) {
                  final bool isSelected =
                      currentlySelectedAssets.contains(asset);
                  return Stack(
                    children: <Widget>[
                      () {
                        Widget item;
                        switch (asset.type) {
                          case AssetType.other:
                            item = const SizedBox.shrink();
                            break;
                          case AssetType.image:
                            item = _imagePreviewItem(asset);
                            break;
                          case AssetType.video:
                            item = _videoPreviewItem(asset);
                            break;
                          case AssetType.audio:
                            item = _audioPreviewItem(asset);
                            break;
                        }
                        return item;
                      }(),
                      AnimatedContainer(
                        duration: kThemeAnimationDuration,
                        curve: Curves.easeInOut,
                        decoration: BoxDecoration(
                          border: isViewing
                              ? Border.all(
                                  color: themeData.colorScheme.secondary,
                                  width: 2.0,
                                )
                              : null,
                          color: isSelected
                              ? null
                              : themeData.colorScheme.surface.withOpacity(0.54),
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget bottomDetailBuilder(BuildContext context) {
    final bool showPreview = selectorProvider.maxAssets > 1;
    final double previewHeight = 90;
    return AnimatedPositioned(
      duration: kThemeAnimationDuration,
      curve: Curves.easeInOut,
      bottom: isDisplayingDetail
          ? 0.0
          : -(Screens.bottomSafeHeight + bottomDetailHeight) +
              (showPreview ? 0 : previewHeight),
      left: 0.0,
      right: 0.0,
      height: Screens.bottomSafeHeight +
          bottomDetailHeight -
          (showPreview ? 0 : previewHeight),
      child: Container(
        padding: EdgeInsets.only(bottom: Screens.bottomSafeHeight),
        color: themeData.canvasColor.withOpacity(0.85),
        child: Column(
          children: <Widget>[
            ChangeNotifierProvider<
                AssetPickerViewerProvider<AssetEntity>>.value(
              value: provider,
              child: Consumer<AssetPickerViewerProvider<AssetEntity>>(
                  builder: (context, value, child) {
                if (isPreviewOnly == false) {
                  selectedAssets.clear();
                  selectedAssets.addAll(value.currentlySelectedAssets);
                }
                if (selectorProvider.maxAssets == 1) {
                  return SizedBox.shrink();
                }
                return SizedBox(
                  height: previewHeight,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 5.0),
                    itemCount: selectedAssets.length,
                    itemBuilder: bottomDetailItemBuilder,
                  ),
                );
              }),
            ),
            Container(
              height: 1.0,
              color: themeData.dividerColor,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    const Spacer(),
                    if (isAppleOS && provider != null)
                      ChangeNotifierProvider<
                          AssetPickerViewerProvider<AssetEntity>>.value(
                        value: provider,
                        child: confirmButton(context),
                      )
                    else
                      selectButton(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// AppBar widget.
  /// 顶栏部件
  Widget appBar(BuildContext context) {
    return AnimatedPositioned(
      duration: kThemeAnimationDuration,
      curve: Curves.easeInOut,
      top: isDisplayingDetail ? 0.0 : -(Screens.topSafeHeight + kToolbarHeight),
      left: 0.0,
      right: 0.0,
      height: Screens.topSafeHeight + kToolbarHeight,
      child: Container(
        padding: EdgeInsets.only(top: Screens.topSafeHeight, right: 12.0),
        color: themeData.canvasColor.withOpacity(0.85),
        child: Row(
          children: <Widget>[
            const BackButton(),
            if (!isAppleOS && specialPickerType == null)
              StreamBuilder<int>(
                initialData: currentIndex,
                stream: pageStreamController.stream,
                builder: (BuildContext _, AsyncSnapshot<int> snapshot) {
                  return Text(
                    '${snapshot.data + 1}/${previewAssets.length}',
                    style: const TextStyle(
                      fontSize: 18.0,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                },
              ),
            const Spacer(),
            if (isAppleOS && provider != null) selectButton(context),
            if (!isAppleOS && provider != null ||
                specialPickerType == SpecialPickerType.wechatMoment)
              confirmButton(context),
          ],
        ),
      ),
    );
  }

  /// It'll pop with [AssetPickerProvider.selectedAssets] when there're any
  /// assets chosen. The [PhotoSelector] will recognize and pop too.
  /// 当有资源已选时，点击按钮将把已选资源通过路由返回。
  /// 资源选择器将识别并一同返回。
  @override
  Widget confirmButton(BuildContext context) {
    return ChangeNotifierProvider<AssetPickerViewerProvider<AssetEntity>>.value(
      value: provider,
      child: Consumer<AssetPickerViewerProvider<AssetEntity>>(
        builder: (
          BuildContext _,
          AssetPickerViewerProvider<AssetEntity> provider,
          Widget __,
        ) {
          return MaterialButton(
            minWidth: () {
              if (specialPickerType == SpecialPickerType.wechatMoment) {
                return 48.0;
              }
              return provider.isSelectedNotEmpty ? 48.0 : 20.0;
            }(),
            height: 32.0,
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            color: () {
              if (specialPickerType == SpecialPickerType.wechatMoment) {
                return themeData.colorScheme.secondary;
              }
              return (provider.isSelectedNotEmpty ||
                      selectorProvider.maxAssets == 1)
                  ? themeData.colorScheme.secondary
                  : themeData.dividerColor;
            }(),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(3.0),
            ),
            child: Text(
              () {
                if (specialPickerType == SpecialPickerType.wechatMoment) {
                  return Constants.textDelegate.confirm;
                }
                if (selectorProvider.maxAssets == 1) {
                  return '${Constants.textDelegate.confirm}';
                }
                if (provider.isSelectedNotEmpty) {
                  return '${Constants.textDelegate.confirm}'
                      '(${provider.currentlySelectedAssets.length}'
                      '/'
                      '${selectorProvider.maxAssets})';
                }
                return Constants.textDelegate.confirm;
              }(),
              style: TextStyle(
                color: () {
                  if (specialPickerType == SpecialPickerType.wechatMoment) {
                    return themeData.textTheme.bodyText1.color;
                  }
                  return provider.isSelectedNotEmpty
                      ? themeData.textTheme.bodyText1.color
                      : themeData.textTheme.caption.color;
                }(),
                fontSize: 17.0,
                fontWeight: FontWeight.normal,
              ),
            ),
            onPressed: () {
              if (specialPickerType == SpecialPickerType.wechatMoment) {
                Navigator.of(context).pop(<AssetEntity>[currentAsset]);
                return;
              }
              if (selectorProvider.maxAssets == 1) {
                Navigator.of(context).pop(<AssetEntity>[currentAsset]);
              } else if (provider.isSelectedNotEmpty) {
                Navigator.of(context).pop(provider.currentlySelectedAssets);
              }
            },
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          );
        },
      ),
    );
  }

  /// Select button for apple OS.
  /// 苹果系列系统的选择按钮
  Widget _appleOSSelectButton(bool isSelected, AssetEntity asset) {
    return Padding(
      padding: const EdgeInsets.only(right: 10.0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (isSelected) {
            provider.unSelectAssetEntity(asset);
          } else {
            if (provider.currentlySelectedAssets.length <
                selectorProvider.maxAssets) {
              provider.selectAssetEntity(asset);
            }
          }
        },
        child: AnimatedContainer(
          duration: kThemeAnimationDuration,
          width: 28.0,
          decoration: BoxDecoration(
            border: !isSelected
                ? Border.all(
                    color: themeData.iconTheme.color,
                  )
                : null,
            color: isSelected ? themeData.buttonColor : null,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: isSelected && isPreviewOnly
                ? Text(
                    (currentIndex + 1).toString(),
                    style: const TextStyle(
                      fontSize: 16.0,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : const Icon(Icons.check, size: 20.0),
          ),
        ),
      ),
    );
  }

  /// Select button for Android.
  /// 安卓系统的选择按钮
  Widget _androidSelectButton(bool isSelected, AssetEntity asset) {
    return RoundedCheckbox(
      value: isSelected,
      onChanged: (bool value) {
        if (isSelected) {
          provider.unSelectAssetEntity(asset);
        } else {
          provider.selectAssetEntity(asset);
        }
      },
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  @override
  Widget selectButton(BuildContext context) {
    return Row(
      children: <Widget>[
        StreamBuilder<int>(
          initialData: currentIndex,
          stream: pageStreamController.stream,
          builder: (BuildContext _, AsyncSnapshot<int> snapshot) {
            return ChangeNotifierProvider<
                AssetPickerViewerProvider<AssetEntity>>.value(
              value: provider,
              child: Selector<AssetPickerViewerProvider<AssetEntity>,
                  List<AssetEntity>>(
                selector: (
                  BuildContext _,
                  AssetPickerViewerProvider<AssetEntity> provider,
                ) =>
                    provider.currentlySelectedAssets,
                builder: (
                  BuildContext _,
                  List<AssetEntity> currentlySelectedAssets,
                  Widget __,
                ) {
                  final AssetEntity asset =
                      previewAssets.elementAt(snapshot.data);
                  final bool isSelected =
                      currentlySelectedAssets.contains(asset);
                  if (selectorProvider.maxAssets == 1) {
                    return SizedBox.shrink();
                  }
                  if (isAppleOS) {
                    return _appleOSSelectButton(isSelected, asset);
                  } else {
                    return _androidSelectButton(isSelected, asset);
                  }
                },
              ),
            );
          },
        ),
        if (!isAppleOS)
          Text(
            Constants.textDelegate.select,
            style: const TextStyle(fontSize: 18.0),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: syncSelectedAssetsWhenPop,
      child: Theme(
        data: themeData,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: themeData.brightness.isDark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          child: Material(
            color: Colors.black,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: ExtendedImageGesturePageView.builder(
                    physics: const CustomScrollPhysics(),
                    controller: pageController,
                    itemCount: previewAssets.length,
                    itemBuilder: assetPageBuilder,
                    onPageChanged: (int index) {
                      currentIndex = index;
                      pageStreamController.add(index);
                    },
                    scrollDirection: Axis.horizontal,
                  ),
                ),
                appBar(context),
                if (selectedAssets != null &&
                    (isAppleOS || (selectorProvider?.maxAssets ?? 0) > 1))
                  bottomDetailBuilder(context),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
