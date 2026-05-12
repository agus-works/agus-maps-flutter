import 'dart:math';

class Rect {
  final int x, y, width, height;
  const Rect(this.x, this.y, this.width, this.height);

  int get right => x + width;
  int get bottom => y + height;
}

class Packer {
  int width;
  int height;
  List<Rect> freeRectangles = [];
  bool overflowDetected = false;

  Packer(this.width, this.height) {
    freeRectangles.add(Rect(0, 0, width, height));
  }

  Rect? pack(int w, int h) {
    if (w == 0 || h == 0) return const Rect(0, 0, 0, 0);

    Rect? bestNode;
    int bestShortSideFit = 2147483647;
    int bestLongSideFit = 2147483647;
    int bestIndex = -1;

    for (int i = 0; i < freeRectangles.length; ++i) {
      final freeRect = freeRectangles[i];
      if (freeRect.width >= w && freeRect.height >= h) {
        int leftoverHoriz = freeRect.width - w;
        int leftoverVert = freeRect.height - h;
        int shortSideFit = min(leftoverHoriz, leftoverVert);
        int longSideFit = max(leftoverHoriz, leftoverVert);

        if (shortSideFit < bestShortSideFit ||
            (shortSideFit == bestShortSideFit &&
                longSideFit < bestLongSideFit)) {
          bestNode = Rect(freeRect.x, freeRect.y, w, h);
          bestShortSideFit = shortSideFit;
          bestLongSideFit = longSideFit;
          bestIndex = i;
        }
      }
    }

    if (bestNode == null) {
      overflowDetected = true;
      return null;
    }

    splitFreeNode(freeRectangles[bestIndex], bestNode);
    freeRectangles.removeAt(bestIndex);

    return bestNode;
  }

  void splitFreeNode(Rect freeNode, Rect usedNode) {
    if (freeNode.width - usedNode.width > freeNode.height - usedNode.height) {
      // Split vertically (Left and Right)
      if (freeNode.width > usedNode.width) {
        freeRectangles.add(
          Rect(
            freeNode.x + usedNode.width,
            freeNode.y,
            freeNode.width - usedNode.width,
            freeNode.height,
          ),
        );
      }
      if (freeNode.height > usedNode.height) {
        freeRectangles.add(
          Rect(
            freeNode.x,
            freeNode.y + usedNode.height,
            usedNode.width,
            freeNode.height - usedNode.height,
          ),
        );
      }
    } else {
      // Split horizontally (Top and Bottom)
      if (freeNode.width > usedNode.width) {
        freeRectangles.add(
          Rect(
            freeNode.x + usedNode.width,
            freeNode.y,
            freeNode.width - usedNode.width,
            usedNode.height,
          ),
        );
      }
      if (freeNode.height > usedNode.height) {
        freeRectangles.add(
          Rect(
            freeNode.x,
            freeNode.y + usedNode.height,
            freeNode.width,
            freeNode.height - usedNode.height,
          ),
        );
      }
    }
  }
}
