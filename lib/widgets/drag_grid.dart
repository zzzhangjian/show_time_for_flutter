import 'package:flutter/material.dart';
import 'dart:async';
import 'package:show_time_for_flutter/widgets/drag_target_move.dart';
import 'package:flutter/rendering.dart';

typedef DragGridViewChild = Widget Function(int position);
typedef EditChangeListener();

//出自 https://github.com/baoolong/DragableGridview
class Data<T> {
  final T data;
  double dragPointX = 0.0;
  double dragPointY = 0.0;
  double lastTimePositionX = 0.0;
  double lastTimePositionY = 0.0;
  GlobalKey containerKey = new GlobalKey();
  GlobalKey containerKeyChild = new GlobalKey();
  bool isLongPress = false;
  bool dragAble = false;

  ///是否隐藏，默认不隐藏
  bool offstage = false;

  Data(
    this.data, {
    this.dragPointX = 0.0,
    this.dragPointY = 0.0,
    this.lastTimePositionX = 0.0,
    this.lastTimePositionY = 0.0,
    this.isLongPress = false,
    this.dragAble = false,
    this.offstage = false,
  });
}

class DragGridView<T> extends StatefulWidget {
  final DragGridViewChild child;
  final List<T> itemBins;

  ///GridView一行显示几个child
  final int crossAxisCount;

  ///为了便于计算 Item之间的空隙都用crossAxisSpacing
  final double crossAxisSpacing;
  final double mainAxisSpacing;

  //cross-axis to the main-axis
  final double childAspectRatio;

  ///编辑开关控制器，可通过点击按钮触发编辑
  final EditSwitchController editSwitchController;

  ///长按触发编辑状态，可监听状态来改变编辑按钮（编辑开关 ，通过按钮触发编辑）的状态
  final EditChangeListener editChangeListener;
  final bool isOpenDragAble;
  final int animationDuration;
  final int longPressDuration;

  ///删除按钮
  final Image deleteIcon;

  DragGridView(
      {Key key,
      @required this.child,
      @required this.itemBins,
      this.crossAxisCount: 4,
      this.crossAxisSpacing: 0.0,
      this.mainAxisSpacing: 0.0,
      this.childAspectRatio: 1.0,
      this.editSwitchController,
      this.editChangeListener,
      this.isOpenDragAble: false,
      this.animationDuration: 300,
      this.longPressDuration: 800,
      this.deleteIcon})
      : assert(child != null, itemBins != null,),
        super(key: key);

  @override
  State<StatefulWidget> createState() => DragGridViewState<T>();
}

class DragGridViewState<T> extends State<DragGridView<T>>
    with SingleTickerProviderStateMixin {
  List<Data<T>> rows = new List<Data<T>>();
  Key myKey;

  var physics = new ScrollPhysics();
  double screenWidth;
  double screenHeight;

  ///在拖动过程中Item position 的位置记录
  List<int> itemPositions;

  ///下面4个变量具体看onTapDown（）方法里面的代码，有具体的备注
  double itemWidth;
  double itemHeight;
  double itemWidthChild;
  double itemHeightChild;

  ///下面2个变量具体看onTapDown（）方法里面的代码，有具体的备注
  double blankSpaceHorizontal;
  double blankSpaceVertical;

  Animation<double> animation;
  AnimationController controller;
  CurvedAnimation curve;

  int startPosition;
  int endPosition;
  bool isRest = false;

  ///覆盖超过1/5则触发动画，宽和高只要有一个满足就可以触发
  //double areaCoverageRatio=1/5;
  Timer timer;
  bool isRemoveItem = false;
  Future _future;

  bool isHideDeleteIcon = true;

  TapDownDetails currentDownDetail;

  @override
  void initState() {
    dataChange();
    _initItemPositions();
    super.initState();
    widget.editSwitchController.dragAbleGridViewState = this;
    controller = new AnimationController(
        vsync: this,
        duration: Duration(milliseconds: widget.animationDuration));
//    curve = new CurvedAnimation(parent: controller, curve: Curves.easeIn);
    animation = new Tween(begin: 0.0, end: 1.0).animate(controller)
      ..addListener(() {
        Data<T> offsetBin;
        int childWidgetPosition;

        if (isRest) {
          if (startPosition > endPosition) {
            for (int i = endPosition; i < startPosition; i++) {
              childWidgetPosition = itemPositions[i];
              offsetBin = rows[childWidgetPosition];
              //图标向右 下移动
              if ((i + 1) % widget.crossAxisCount == 0) {
                offsetBin.lastTimePositionX = -(screenWidth - itemWidth) * 1 +
                    offsetBin.lastTimePositionX;
                offsetBin.lastTimePositionY =
                    (itemHeight + widget.mainAxisSpacing) * 1 +
                        offsetBin.lastTimePositionY;
              } else {
                offsetBin.lastTimePositionX =
                    (itemWidth + widget.crossAxisSpacing) * 1 +
                        offsetBin.lastTimePositionX;
              }
            }
          } else {
            for (int i = startPosition + 1; i <= endPosition; i++) {
              childWidgetPosition = itemPositions[i];
              offsetBin = rows[childWidgetPosition];
              //图标向左 上移动
              if (i % widget.crossAxisCount == 0) {
                offsetBin.lastTimePositionX =
                    (screenWidth - itemWidth) * 1 + offsetBin.lastTimePositionX;
                offsetBin.lastTimePositionY =
                    -(itemHeight + widget.mainAxisSpacing) * 1 +
                        offsetBin.lastTimePositionY;
              } else {
                offsetBin.lastTimePositionX =
                    -(itemWidth + widget.crossAxisSpacing) * 1 +
                        offsetBin.lastTimePositionY;
              }
            }
          }
          return;
        }
        //此代码和上面的代码一样，但是不能提成方法调用 ，已经测试调用方法不会生效
        setState(() {
          //startPosition大于endPosition表明目标位置在上方，图标需要向后退一格
          if (startPosition > endPosition) {
            for (int i = endPosition; i < startPosition; i++) {
              childWidgetPosition = itemPositions[i];
              offsetBin = rows[childWidgetPosition];
              //图标向左 下移动；如果图标处在最右侧，那需要向下移动一层，移动到下一层的最左侧，（开头的地方）
              if ((i + 1) % widget.crossAxisCount == 0) {
                offsetBin.dragPointX =
                    -(screenWidth - itemWidth) * animation.value +
                        offsetBin.lastTimePositionX;
                offsetBin.dragPointY =
                    (itemHeight + widget.mainAxisSpacing) * animation.value +
                        offsetBin.lastTimePositionY;
              } else {
                //↑↑↑如果图标不是处在最右侧，只需要向右移动即可
                offsetBin.dragPointX =
                    (itemWidth + widget.crossAxisSpacing) * animation.value +
                        offsetBin.lastTimePositionX;
              }
            }
          } else {
            //当目标位置在下方时 ，图标需要向前前进一个
            for (int i = startPosition + 1; i <= endPosition; i++) {
              childWidgetPosition = itemPositions[i];
              offsetBin = rows[childWidgetPosition];
              //图标向右 上移动；如果图标处在最左侧，那需要向上移动一层
              if (i % widget.crossAxisCount == 0) {
                offsetBin.dragPointX =
                    (screenWidth - itemWidth) * animation.value +
                        offsetBin.lastTimePositionX;
                offsetBin.dragPointY =
                    -(itemHeight + widget.mainAxisSpacing) * animation.value +
                        offsetBin.lastTimePositionY;
              } else {
                //↑↑↑如果图标不是处在最左侧，只需要向左移动即可
                offsetBin.dragPointX =
                    -(itemWidth + widget.crossAxisSpacing) * animation.value +
                        offsetBin.lastTimePositionX;
              }
            }
          }
        });
      });
    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {});
        isRest = true;
        controller.reset();
        isRest = false;
        if (isRemoveItem) {
          isRemoveItem = false;
          itemPositions.remove(startPosition);
          onPanEndEvent(startPosition);
        } else {
          int dragPosition = itemPositions[startPosition];
          itemPositions.remove(startPosition);
          itemPositions.insert(endPosition, dragPosition);
          //手指未抬起来（可能会继续拖动），这时候end的位置等于Start的位置
          startPosition = endPosition;
        }
      }
    });
  }

  void _initItemPositions() {
    itemPositions = new List();
    for (int i = 0; i < rows.length; i++) {
      itemPositions.add(i);
    }
  }

  @override
  void didUpdateWidget(DragGridView<T> oldWidget) {
    dataChange();
    super.didUpdateWidget(oldWidget);
  }

  dataChange() {
    List data = widget.itemBins;
    rows = data.map((it) {
      return new Data<T>(it);
    }).toList();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Size screenSize = MediaQuery.of(context).size;
    screenWidth = screenSize.width;
    screenHeight = screenSize.height;
  }

  void _handLongPress(int index) {
    if (rows[index].isLongPress) {
      setState(() {
        rows[index].dragAble = true;
        startPosition = index;
        if (widget.editChangeListener != null && isHideDeleteIcon == true) {
          widget.editChangeListener();
        }
        isHideDeleteIcon = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.crossAxisCount,
        childAspectRatio: widget.childAspectRatio,
        crossAxisSpacing: widget.crossAxisSpacing,
        mainAxisSpacing: widget.mainAxisSpacing,
      ),
      delegate: SliverChildBuilderDelegate(
        (BuildContext context, int index) {
          return GestureDetector(
            onTapDown: widget.isOpenDragAble
                ? (detail) {
                    currentDownDetail = detail;
                  }
                : null,
            onPanUpdate: widget.isOpenDragAble
                ? (updateDetail) {
                  }
                : null,
            onTapUp: widget.isOpenDragAble
                ? (tapUpDetails) {
                    handleOnTapUp(index);
                  }
                : null,
            onPanEnd: widget.isOpenDragAble
                ? (upDetail) {
                    handleOnPanEndEvent(index);
                  }
                : null,
            child: LongPressCustomDraggable<Data>(
                key: myKey,
                childWhenDragging: new Container(),
                child: _getGridChild(context, index),
                feedback: _getFeedback(index, context),
                data: rows[index],
                onMove: (Offset offset) {
                  handleOnPanUpdateEvent(index, offset);
                },
                onDragStarted: () {
                  handleOnTapDownEvent(index, currentDownDetail);
                },
                onDragCompleted: () {
//                  handleOnPanEndEvent(index);
                },
                onCustomDraggableCanceled: (_, _2) {
//                  handleOnTapUp(index);
                  handleOnPanEndEvent(index);
                }),
          );
        },
        childCount: rows.length,
      ),
    );
  }

  _getGridChild(BuildContext context, int index) {
    Data<T> data = rows[index];
    var dragPointX = data.dragPointX;
    var dragPointY = data.dragPointY;
    return CustomDragTarget<Data>(onWillAccept: (data) {
      return true;
    }, builder: (BuildContext context, List candidateData, List rejectedData) {
      return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
        return new Container(
          alignment: Alignment.center,
          key: data.containerKey,
          child: new Center(
            child: new Container(
              key: data.containerKeyChild,
              transform: new Matrix4.translationValues(dragPointX, dragPointY, 0.0),
              child: new Stack(
                alignment: Alignment.topRight,
                children: <Widget>[
                  widget.child(index),
                ],
              ),
            ),
          ),
        );
      });
    });
  }

  _getFeedback(int index, BuildContext context) {
//    Data data = rows[index];
//    getWidgetsSize(data);
    return SizedBox(
        width: itemWidth, height: itemHeight, child: widget.child(index));
  }

  void handleOnPanEndEvent(int index) {
    Data data = rows[index];
    data.isLongPress = false;
    if (!data.dragAble) {
      data.dragPointX = 0.0;
      data.dragPointY = 0.0;
    } else {
      onPanEndEvent(index);
    }
  }

  void handleOnTapUp(int index) {
    Data data = rows[index];
    data.isLongPress = false;
    if (!isHideDeleteIcon) {
      //计算手指点下去后，控件应该偏移多少像素
      data.dragPointY = 0.0;
      data.dragPointX = 0.0;
    }
  }

  void handleOnPanUpdateEvent(int index, Offset updateDetail) {
    Data data = rows[index];
    data.isLongPress = false;
    if (data.dragAble) {
      double dragPointX = data.dragPointX += updateDetail.dx;
      double dragPointY = data.dragPointY += updateDetail.dy;
//      if (timer != null && timer.isActive) {
//        timer.cancel();
//      }
      if (controller.isAnimating) {
        return;
      }
      onFingerPause(index, dragPointX, dragPointY);
//      timer = new Timer(Duration(milliseconds: 100), () {
//        onFingerPause(index, dragPointX, dragPointY);
//      });
      rows.remove(index);
      setState(() {});
    }
  }

  ///停止滑动时，处理是否需要动画等
  void onFingerPause(
    int index,
    double dragPointX,
    double dragPointY,
  ) async {
    //边框和父布局之间的空白部分  +  gridView Item之间的space   +  相邻Item边框和父布局之间的空白部分
    //所以 一个View和相邻View空白的部分计算如下 ，也就是说大于这个值 两个Item则能相遇叠加
    double xBlankPlace = blankSpaceHorizontal * 2 + widget.crossAxisSpacing;
    double yBlankPlace = blankSpaceVertical * 2 + widget.mainAxisSpacing;
    int y = geyYTransferItemCount(index, yBlankPlace, dragPointY);
    int x = geyXTransferItemCount(index, xBlankPlace, dragPointX);
    //2.动画正在进行时不能进行动画 3. 计算错误时，终点坐标小于或者大于itemBins.length时不能动画
//    if (endPosition != x + y &&
//        !controller.isAnimating &&
//        x + y < widget.itemBins.length &&
//        x + y >= 0 &&
//        rows[index].dragAble) {
//      endPosition = x + y;
//      _future = controller.forward();
//    }
    endPosition = x + y;
    _future = controller.forward();
  }

  int geyXTransferItemCount(int index, double xBlankPlace, double dragPointX) {
    //最大边界 和 最小边界
    //double maxBoundWidth = itemWidthChild * (1-areaCoverageRatio);
    //double minBoundWidth = itemWidthChild * areaCoverageRatio;

    //是否越过空白间隙，未越过则表示在原地，或覆盖自己原位置的一部分，未拖动到其他Item上，或者已经拖动过多次现在又拖回来了；越过则有多种情况
    if (dragPointX.abs() > xBlankPlace) {
      if (dragPointX > 0) {
        //↑↑↑表示移动到自己原位置的右手边
        return checkXAxleRight(index, xBlankPlace, dragPointX);
      } else {
        //↑↑↑表示移动到自己原位置的左手边
        return checkXAxleLeft(index, xBlankPlace, dragPointX);
      }
    } else {
      //↑↑↑连一个空白的区域都未越过 肯定是呆在自己的原位置，返回index
      return 0;
    }
  }

  ///当被拖动到自己位置右侧时
  int checkXAxleRight(int index, double xBlankPlace, double dragPointX) {
    double aSection = itemWidthChild + xBlankPlace;
    double rightTransferDistance = dragPointX.abs() + itemWidthChild;
    //计算左右边框的余数
    double rightBorder = rightTransferDistance % aSection;
    double leftBorder = dragPointX.abs() % aSection;
    //与2个item有粘连时，计算占比多的就是要目标位置
    if (rightBorder < itemWidthChild && leftBorder < itemWidthChild) {
      if (itemWidthChild - leftBorder > rightBorder) {
        //left占比多，那左侧未将要动画的目标位置
        return (dragPointX.abs() / aSection).floor();
      } else {
        //right占比多
        return (rightTransferDistance / aSection).floor();
      }
    } else if (rightBorder > itemWidthChild && leftBorder < itemWidthChild) {
      //left粘连，右边的边框在空白区域
      return (dragPointX.abs() / aSection).floor();
    } else if (rightBorder < itemWidthChild && leftBorder > itemWidthChild) {
      //right粘连，左侧的边框在空白区域
      return (rightTransferDistance / aSection).floor();
    } else {
      //左右两边均没有粘连时，说明左右两边处于空白区域，返回0即可
      return 0;
    }
  }

  ///X轴方向上，当被拖动到自己位置左侧时
  int checkXAxleLeft(int index, double xBlankPlace, double dragPointX) {
    double aSection = xBlankPlace + itemWidthChild;

    double leftTransferDistance = dragPointX.abs() + itemWidthChild;

    //计算左右边框的余数
    double leftBorder = leftTransferDistance % aSection;
    double rightBorder = dragPointX.abs() % aSection;
    //与2个item有粘连时，计算占比多的就是要目标位置
    if (rightBorder < itemWidthChild && leftBorder < itemWidthChild) {
      if (itemWidthChild - rightBorder > leftBorder) {
        //right占比多，那右侧为将要动画的目标位置
        return -(dragPointX.abs() / aSection).floor();
      } else {
        //left占比多
        return -(leftTransferDistance / aSection).floor();
      }
    } else if (rightBorder > itemWidthChild && leftBorder < itemWidthChild) {
      //left粘连，右边的边框在空白区域
      return -(leftTransferDistance / aSection).floor();
    } else if (rightBorder < itemWidthChild && leftBorder > itemWidthChild) {
      //right粘连，左侧的边框在空白区域
      return -(dragPointX.abs() / aSection).floor();
    } else {
      //左右两边均没有粘连时，说明左右两边处于空白区域，返回0即可
      return 0;
    }
  }

  ///计算Y轴方向需要移动几个Item
  /// 1. 目标拖动距离拖动不满足， 2. 拖动到其他Item的，3. 和任何Item都没有粘连，5.和多个item有重叠 等4种情况
  /// 还要考虑一点就是 虽然Y轴不满足1/5--4/5覆盖率，但是X轴满足
  int geyYTransferItemCount(int index, double yBlankPlace, double dragPointY) {
    //最大边界 和 最小边界
    //double maxBoundHeight = itemHeightChild * (1-areaCoverageRatio);
    //double minBoundHeight = itemHeightChild * areaCoverageRatio;

    //上下边框是否都满足 覆盖1/5--4/5高度的要求
    //bool isTopBoundLegitimate = topBorder > minBoundHeight && topBorder < maxBoundHeight;
    //bool isBottomBoundLegitimate = bottomBorder > minBoundHeight && bottomBorder < maxBoundHeight;

    //是否越过空白间隙，未越过则表示在原地，或覆盖自己原位置的一部分，未拖动到其他Item上，或者已经拖动过多次现在又拖回来了；越过则有多种情况
    if (dragPointY.abs() > yBlankPlace) {
      //↑↑↑越过则有多种情况↓↓↓
      if (dragPointY > 0) {
        //↑↑↑表示拖动的Item现在处于原位置之下
        return checkYAxleBelow(index, yBlankPlace, dragPointY);
      } else {
        //↑↑↑表示拖动的Item现在处于原位置之上
        return checkYAxleAbove(index, yBlankPlace, dragPointY);
      }
    } else {
      //↑↑↑未越过 返回index
      return index;
    }
  }

  ///Y轴上当被拖动到原位置之上时，计算拖动了几行
  int checkYAxleAbove(int index, double yBlankPlace, double dragPointY) {
    double aSection = yBlankPlace + itemHeightChild;

    double topTransferDistance = dragPointY.abs() + itemHeightChild;
    //求下边框的余数，余数小于itemHeightChild，表示和下面的item覆盖，余数大于itemHeightChild，表示下边框处于空白的区域
    double topBorder = (topTransferDistance) % aSection;
    //求上边框的余数 ，余数小于itemHeightChild，表示和上面的Item覆盖 ，余数大于itemHeightChild，表示上边框处于空白区域
    double bottomBorder = dragPointY.abs() % aSection;
    if (topBorder < itemHeightChild && bottomBorder < itemHeightChild) {
      //↑↑↑同时和2和item覆盖（上下边框均在覆盖区域）
      if (itemHeightChild - bottomBorder > topBorder) {
        //↑↑↑粘连2个  要计算哪个占比多,topBorder越小 覆盖面积越大  ，bottomBorder越大  覆盖面积越大;
        //下边框占比叫较大
        return index -
            (dragPointY.abs() / aSection).floor() * widget.crossAxisCount;
      } else {
        //↑↑↑上边框占比大
        return index -
            (topTransferDistance / aSection).floor() * widget.crossAxisCount;
      }
    } else if (topBorder > itemHeightChild && bottomBorder < itemHeightChild) {
      //↑↑↑下边框在覆盖区,上边框在空白区域。
      return index -
          (dragPointY.abs() / aSection).floor() * widget.crossAxisCount;
    } else if (topBorder < itemHeightChild && bottomBorder > itemHeightChild) {
      //↑↑↑上边框在覆盖区域,下边框在空白区域
      return index -
          (topTransferDistance / aSection).floor() * widget.crossAxisCount;
    } else {
      //和哪个Item都没有覆盖，上下边框都在空白的区域。返回Index即可
      return index;
    }
  }

  /// 还要考虑一点就是 虽然Y轴不满足1/5--4/5覆盖率，但是X轴满足，所以返回的时候同时返回目标index 和 是否满足Y的覆盖条件
  int checkYAxleBelow(int index, double yBlankPlace, double dragPointY) {
    double aSection = yBlankPlace + itemHeightChild;

    double bottomTransferDistance = dragPointY.abs() + itemHeightChild;

    //求下边框的余数，余数小于itemHeightChild，表示和下面的item覆盖，余数大于itemHeightChild，表示下边框处于空白的区域
    double bottomBorder = bottomTransferDistance % aSection;
    //求上边框的余数 ，余数小于itemHeightChild，表示和上面的Item覆盖 ，余数大于itemHeightChild，表示上边框处于空白区域
    double topBorder = dragPointY.abs() % aSection;

    if (bottomBorder < itemHeightChild && topBorder < itemHeightChild) {
      //↑↑↑同时和2和item覆盖（上下边框均在覆盖区域）
      if (itemHeightChild - topBorder > bottomBorder) {
        //↑↑↑粘连2个  要计算哪个占比多,topBorder越小 覆盖面积越大  ，bottomBorder越大  覆盖面积越大;
        //↑↑↑上面占比大
        return index +
            (dragPointY.abs() / aSection).floor() * widget.crossAxisCount;
      } else {
        //↑↑↑下面占比大
        return index +
            (bottomTransferDistance / aSection).floor() * widget.crossAxisCount;
      }
    } else if (topBorder > itemHeightChild && bottomBorder < itemHeightChild) {
      //↑↑↑下边框在覆盖区 , 上边框在空白区域
      return index +
          (bottomTransferDistance / aSection).floor() * widget.crossAxisCount;
    } else if (topBorder < itemHeightChild && bottomBorder > itemHeightChild) {
      //topBorder<itemHeightChild
      //↑↑↑上边框在覆盖区域 ,下边框在空白区域
      return index +
          (dragPointY.abs() / aSection).floor() * widget.crossAxisCount;
    } else {
      //↑↑↑和哪个Item都没有覆盖，上下边框都在空白的区域。返回Index即可
      return index;
    }
  }

  void handleOnTapDownEvent(int index, TapDownDetails detail) {
    Data data = rows[index];
    getWidgetsSize(data);
    if (!isHideDeleteIcon) {
      //获取控件在屏幕中的y坐标
      var translation = data.containerKey.currentContext
          .findRenderObject()
          .getTransformTo(null)
          .getTranslation();
      double y = translation.y;
      double x = translation.x;
      //计算手指点下去后，控件应该偏移多少像素
      data.dragPointX = detail.globalPosition.dx - x - itemWidth / 2;
//      data.dragPointX = detail.dx - x - itemWidth / 2;
      data.dragPointY = detail.globalPosition.dy - y - itemHeight / 2;
//      data.dragPointY = detail.dy - y - itemHeight / 2;
    }
    //标识长按事件开始
    data.isLongPress = true;
    //将可拖动标识置为false；（dragAble 为 true时 控件可拖动 ，暂时置为false  等达到长按时间才视为需要拖动）
    data.dragAble = false;
    endPosition = index;
    _handLongPress(index);
  }

  void getWidgetsSize(Data pressItemBin) {
    //获取 不 带边框的Container的宽度
    var size = pressItemBin.containerKey.currentContext
        .findRenderObject()
        .paintBounds
        .size;
    itemHeight = size.height;
    itemWidth = size.width;
    //获取  带边框 的Container的宽度，就是可见的Item视图的宽度
    var sizeChild = pressItemBin.containerKeyChild.currentContext
        .findRenderObject()
        .paintBounds
        .size;
    itemWidthChild = sizeChild.width;
    itemHeightChild = sizeChild.height;
    //获取 不带边框  和它的子View （带边框 的Container）左右两边的空白部分的宽度
    blankSpaceHorizontal = (itemWidth - itemWidthChild) / 2;
    blankSpaceVertical = (itemHeight - itemHeightChild) / 2;
  }

  ///拖动结束后，根据 itemPositions 里面的排序，将itemBins重新排序
  ///并重新初始化 itemPositions
  void onPanEndEvent(index) async {
    rows[index].dragAble = false;
    if (controller.isAnimating) {
      return _future;
    }
    setState(() {
      List<Data<T>> itemBi = new List();
      Data<T> bin;
      for (int i = 0; i < itemPositions.length; i++) {
        bin = rows[itemPositions[i]];
        bin.dragPointX = 0.0;
        bin.dragPointY = 0.0;
        bin.lastTimePositionX = 0.0;
        bin.lastTimePositionY = 0.0;
        itemBi.add(bin);
      }
      rows.clear();
      rows.addAll(itemBi);
      _initItemPositions();
    });
  }

  //外部使用EditSwitchController控制编辑状态
  ///当调用该方法时 将GridView Item上的删除图标的状态取非 来改变状态
  void changeDeleteIconState() {
    setState(() {
      isHideDeleteIcon = !isHideDeleteIcon;
    });
  }
}

class EditSwitchController {
  DragGridViewState dragAbleGridViewState;

  void editStateChanged() {
    dragAbleGridViewState.changeDeleteIconState();
  }
}
