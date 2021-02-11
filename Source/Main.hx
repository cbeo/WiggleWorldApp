package;

import haxe.ds.Option;
import motion.Actuate;
import openfl.display.GraphicsPath;
import openfl.display.SimpleButton;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.events.KeyboardEvent;
import openfl.events.MouseEvent;
import openfl.events.TimerEvent;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.ui.Keyboard;
import openfl.utils.Timer;

using Lambda;

typedef PointType = { x:Float, y:Float};
typedef HasVelocity =  {velocity: PointType};
typedef Circle = PointType & {radius:Float};
typedef HasColor = {color: Int};
typedef ColoredCircle = HasColor & Circle;



class Button extends SimpleButton
{
  static var overColor:Int = 0xdddddd;
  static var upColor:Int = 0xeeeeee;
  static var downColor:Int = 0xcccccc;

  static function textBox
  (text:String,
   bgColor:Int = 0xFFFFFF,
   ?textFormat:TextFormat,
   ?borderRadius:Float = 0.0,
   ?padding:Float = 40.0,
   ?borderThickness:Float = 0.0,
   ?borderColor:Int = 0
  ):Sprite
  {
    var tf = new TextField();
    tf.multiline = false;
    tf.autoSize = openfl.text.TextFieldAutoSize.CENTER;
    tf.selectable = false;
    tf.text = text;

    if (textFormat != null)
      tf.setTextFormat( textFormat );

    var s = new Sprite();
    s.graphics.beginFill( bgColor );

    if (borderThickness > 0)
      s.graphics.lineStyle( borderThickness, borderColor);

    s.graphics.drawRoundRect(0, 0,
                             tf.textWidth + padding,
                             tf.textHeight + padding,
                             borderRadius,
                             borderRadius );
    s.graphics.endFill();

    tf.x = (s.width - tf.textWidth) / 2;
    tf.y = (s.height - tf.textHeight) / 2;

    s.addChild( tf );
    return s;
  }
  
  public function new (text:String)
  {
    var textFormat = new TextFormat(null, 25);

    var over = textBox(text, overColor, textFormat, 10.0, 50, 2 );
    var up = textBox(text, upColor, textFormat, 10.0, 50, 2);
    var down = textBox(text, downColor, textFormat, 10.0, 50, 2);

    super( up , over, down, over);
    this.enabled = true;
  }

}

class Wiggler extends Sprite
{
  static inline var RADIUS_DRAW_THRESHHOLD = 25;
  
  var path:Array<Point> = [];

  var radiusGradient:Float = 3.0;
  var radiiSizes:Int = 25;

  var dontDrawLargerThanFactor = 0.2;
  var circles:Array<ColoredCircle> = [];

  public function new (path:Array<Point>)
  {
    super();
    this.path = GeomTools.translatePathToOrigin( path );
    addCircles();
    render();
  }

  // A circle is valid if it is contained within the boundary of the
  // path and if it does not intersect any other circles.
  function isValidCircle( circ:ColoredCircle ): Bool
  {
    return circleInsideClosedPath( circ) &&
      !circleIntersectsCircles( circ );
  }

  function circleInsideClosedPath( circ ): Bool
  {
    return GeomTools.pointInsideClosedPath( circ, path) &&
      !GeomTools.circleIntersectsPath(circ, path);
  }
  
  function circleIntersectsCircles( circ ): Bool
  {
    for (c in circles)
      if (GeomTools.circlesIntersect( c, circ))
        return true;

    return false;
  }

  function randomCircle( box:Rectangle, radius:Float): ColoredCircle
  {
    var pt = GeomTools.randomPointInRect( box );
    return {x:pt.x, y:pt.y, color: Std.int(Math.random() * 0xFFFFFF), radius:radius};
  }

  function addCircles()
  {
    circles = [];
    if (path.length > 2)
      {
        var bbox = GeomTools.pathBoundingBox( path );
        var rad = radiusGradient * radiiSizes;
        var step = 1.25;
        while (rad > 0)
          {
            for (cx in 0...Std.int(bbox.width / (step * rad)))
              for (cy in 0...Std.int(bbox.height / (step * rad)))
                {
                  var circ = {
                  x: cx * step * rad,
                  y:cy * step * rad,
                  radius:rad,
                  color: Std.int(Math.random() * 0xFFFFFF)
                  };

                  if (isValidCircle( circ )) circles.push( circ );
                }
            rad -= radiusGradient;
          }
      }
  }


  public function render ()
  {
    if (path.length == 0) return;
    
    graphics.clear();
    var graphicsPath = new GraphicsPath();
    graphicsPath.moveTo( path[0].x, path[0].y);
    for (i in 1...path.length)
      graphicsPath.lineTo( path[i].x, path[i].y);

    graphics.lineStyle(8.0);
    graphicsPath.lineTo( path[0].x, path[0].y);

    graphics.drawPath( graphicsPath.commands, graphicsPath.data );

    var dontDrawLargerThan = radiiSizes * radiusGradient * dontDrawLargerThanFactor;
    graphics.lineStyle(2.0);
    for (circ in circles)
      if (circ.radius <= dontDrawLargerThan)
        {
          graphics.beginFill( circ.color, 0.75);
          graphics.drawCircle( circ.x, circ.y, circ.radius);
        }    
  }

}

class DrawingScreen extends Sprite
{

  /* the prupose of which is to produce a path of a closed polygon
     suitable for passing in as the "skin" of a wiggler. */
  
  var path: Array<Point> = [];

  var candidateWiggler:Wiggler;

  var holdPath:Bool = false;

  public function new ()
  {
    super();
    addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
    addEventListener(MouseEvent.MOUSE_UP, onMouseUp);
    addEventListener(MouseEvent.MOUSE_OUT, onMouseUp);
    addEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
    addEventListener(Event.ADDED_TO_STAGE, maximizeHitArea);
  }

  /* Event Handling */
  
  static inline var sampleRate:Float = 0.01;
  static inline var sampleGap:Float = 5.0;
  static inline var bgColor:Int = 0xFFFFFF;

  var drawing = false;
  var timestamp:Float;

  function maximizeHitArea(e)
  {
    var hitBox = new Sprite();
    hitBox.graphics.beginFill(0);
    hitBox.graphics.drawRect( 0, 0, stage.stageWidth, stage.stageHeight);
    hitBox.mouseEnabled = false;
    this.hitArea = hitBox;
  }

  function onMouseDown (e)
  {
    refresh();
    drawing = true;
    timestamp = haxe.Timer.stamp();
    path = [ new Point(e.localX, e.localY) ];

    graphics.lineStyle(2, 0);
    graphics.moveTo( path[0].x, path[0].y );
  }

  function refresh ()
  {
    Actuate.stop(this); 
    if (candidateWiggler != null)
      {
        removeChild( candidateWiggler );
        candidateWiggler = null;
      }
    graphics.clear();
    alpha = 1.0;
    visible = true;
    path = [];
    holdPath = false;
  }

  function fadeAndRefresh()
  {
    Actuate
      .tween(this, 0.5, {alpha: 0})
      .onComplete( refresh );
  }

  function onMouseUp (e)
  {
    drawing = false;
    if (!holdPath) fadeAndRefresh();
  }
  
  function clearAndRenderPath()
  {
    graphics.clear();
    graphics.lineStyle(2, 0);
    graphics.moveTo(path[0].x, path[0].y);
    for (i in 1...path.length)
      graphics.lineTo(path[i].x, path[i].y);
    graphics.lineTo(path[0].x, path[0].y);
  }

  function onMouseMove (e)
  {
    if (!drawing) return;

    var stamp = haxe.Timer.stamp();
    var pt = new Point( e.localX, e.localY);
    if ((stamp - timestamp > sampleRate) &&
        Point.distance(pt, path[path.length - 1]) >= sampleGap)
      {
        var intersectIndex = GeomTools.findSelfIntersection( path, pt );
        if (intersectIndex != null)
          {
            drawing = false;
            holdPath = true;
            var intersectionPt =
              GeomTools.linesIntersectAt( path[intersectIndex],
                                          path[intersectIndex + 1],
                                          path[path.length -1], pt);

            path = path.slice( intersectIndex );

            if (intersectionPt != null)
              {
                path.push(intersectionPt);
                graphics.lineTo( intersectionPt.x, intersectionPt.y);
              }
            else
              graphics.lineTo( pt.x, pt.y );

            //clearAndRenderPath();
            createAndPresentWiggler();
            return; // to return early
          }

        timestamp = stamp;
        path.push( pt );
        graphics.lineTo( pt.x, pt.y);
      }
  }


  function createAndPresentWiggler()
  {
    clearAndRenderPath();

    var bbox = GeomTools.pathBoundingBox( path );

    candidateWiggler = new Wiggler( path );
    candidateWiggler.x = bbox.x;
    candidateWiggler.y = bbox.y;

    //graphics.clear();

    addChild( candidateWiggler );

  }
}

enum Line {
  Vertical(xVal:Float);
  Horizontal(yVal:Float);
  Sloped(slop:Float,yIntercept:Float);
}

class GeomTools
{

  public static function randomBetween(lo:Float,hi:Float):Float
  {
    if (hi < lo) return randomBetween(hi, lo);

    return Math.random() * (hi - lo) + lo;   
  }

  public static function circlesIntersect<C1:Circle,C2:Circle>(c1:C1,c2:C2):Bool
  {
    var d = dist(c1,c2);
    return d < c1.radius + c2.radius;
  }

  public static function pathBoundingBox( path:Array<Point> ):Null<Rectangle>
  {
    if (path.length ==0) return null;
    var left  = path[0].x;
    var right = left;
    var top = path[0].y;
    var bottom = top;

    for (pt in path)
      {
        left = Math.min( left, pt.x);
        right = Math.max( right, pt.x);
        top = Math.min( top, pt.y);
        bottom = Math.max( bottom, pt.y);
      }
    return new Rectangle(left, top, right - left, bottom - top);
  }

  public static function randomPointInRect( rect:Rectangle):Point
  {
    return new Point( Math.random() * rect.width + rect.x,
                      Math.random() * rect.height + rect.y);    
  }

  // a point is inside a closed path if, when a linesegment connecting
  // that point to the origin is drawn, the number of intersections
  // of that line and the path is odd.
  public static function pointInsideClosedPath< T: PointType> (pt: T, path:Array<Point>):Bool
  {
    if (path.length < 2) return false;
    
    var intersections = 0;
    var origin : PointType = {x:0, y:0};

    for (i in 0...path.length - 1)
      if (segmentsIntersect( origin, pt, path[i], path[i + 1]))
        intersections += 1;

    if (segmentsIntersect( origin, pt, path[path.length - 1], path[0]))
      intersections += 1;

    return intersections % 2 == 1;
  }

  public static function circleIntersectsPath<T:Circle>
  ( circ:T, path:Array<Point>):Bool
  {
    for (i in 0...path.length - 1)
      {
        if (circleContainsPt( circ, path[i]) ||
            circleContainsPt( circ, path[i + 1]))
          return true;

        if (circleIntersectsLineSegment(circ, path[i], path[i+1]))
          return true;
      }
    return false;
  }

  public static function isBetween( a:Float, b:Float, c:Float):Bool
  {
    return (a <= b && b <= c) || (c <= b && b <= a);
  }

  // choosing to do this b/c it will benefit from any efficiency gains that
  // may be introduced into openfl's Point.distance method in the future:
  static var distPt1:Point;
  static var distPt2:Point;
  public static function dist<P1:PointType, P2:PointType>(p1:P1,p2:P2):Float
  {
    if (distPt1 == null)
      {
        distPt1 = new Point();
        distPt2 = new Point();
      }

    distPt1.x = p1.x;
    distPt1.y = p1.y;

    distPt2.x = p2.x;
    distPt2.y = p2.y;

    return Point.distance( distPt1, distPt2);
  }

  public static function circleContainsPt<C:Circle,P:PointType>
    (circ:C, pt:P):Bool
  {
    return dist(circ, pt) <= circ.radius;
  }

  public static function circleIntersectsLineSegment<T:Circle, U:PointType>
    ( circ: T, p1:U, p2:U):Bool
  {
    // if either enddpoint is in the circle, then we count an
    // intersection.  note, that this means that even if the circle
    // contains the whole segment, we count this as an intersection.
    if (circleContainsPt(circ,p1) || circleContainsPt(circ, p2))
      return true;

    switch (lineOfSegment(p1, p2))
      {
      case Vertical(xVal):
        return Math.abs(circ.x - xVal) <= circ.radius && isBetween(p1.y, circ.y, p2.y);

      case Horizontal(yVal):
        return Math.abs(circ.y - yVal) <= circ.radius && isBetween(p1.x, circ.x, p2.x);

      case Sloped(m, yInt):
        var a = m * m + 1;
        var k = yInt - circ.y;
        var b = 2 * (m*k - circ.x);
        var c = k * k + circ.x * circ.x - circ.radius * circ.radius;

        var discriminant = b * b - 4 * a * c;
        return discriminant >= 0;
      }
  }

  public static function ptEquals<P1:PointType, P2:PointType>(a:P1,b:P2):Bool
  {
    return a.x == b.x && a.y == b.y;
  }

  public static function lineOfSegment<P1:PointType, P2:PointType> ( a:P1, b:P2 ): Null<Line>
  {
    if (ptEquals(a, b )) return null;
    if (a.x == b.x) return Vertical(a.x);
    if (a.y == b.y) return Horizontal(a.y);

    var slope = (b.y - a.y) / (b.x - a.x);
    var yIntercept = a.y - slope * a.x;
    return Sloped(slope, yIntercept);
  }

  public static function isCounterClockwiseOrder
  <P1:PointType,P2:PointType,P3:PointType>
  (a:P1,b:P2,c:P3):Bool {
    return (b.x - a.x) * (c.y - a.y) > (b.y - a.y) * (c.x - a.x);
  }

  public static function segmentsIntersect
  <P1:PointType,P2:PointType,P3:PointType,P4:PointType>
  (a:P1,b:P2,c:P3,d:P4):Bool
  {
    return (isCounterClockwiseOrder( a, c, d) != isCounterClockwiseOrder(b, c, d)) &&
      (isCounterClockwiseOrder( a ,b, c) != isCounterClockwiseOrder(a, b, d));
  }


  public static function pathIsCounterClockwise( path: Array<Point> ) : Bool
  {
    return path.length > 2 && isCounterClockwiseOrder(path[0], path[1], path[2]);
  }


  public static function linesIntersectAt
  <P1:PointType,P2:PointType,P3:PointType,P4:PointType>
    (a:P1,b:P2,c:P3,d:P4):Null<Point>
  {
    var segments = [lineOfSegment(a, b), lineOfSegment(c, d)];
    switch (segments)
      {
      case [Sloped(m1,b1), Sloped(m2,b2)]:
        var x = (b2 - b1) / (m1 - m2);
        var y = m1 * x + b1;
        return new Point(x, y);

      case [Sloped(m,b), Horizontal(y)] | [Horizontal(y) , Sloped(m, b)]:
        var x = (y - b) / m;
        return new Point(x,y);

      case [Sloped(m,b), Vertical(x)] | [Vertical(x), Sloped(m,b)]:
        var y = m * x + b;
        return new Point(x, y);

      case [Horizontal(y), Vertical(x)] | [Vertical(x), Horizontal(y)]:
        return new Point(x, y);

      default:
        return null;
      }
  }

  // given a path and a point, check of the line between the last
  // point in tha path and the provided point intersects the path.  If
  // it does, the last index in the path checked is returned.
  public static function findSelfIntersection
  ( path:Array<Point>, pt:Point ) : Null<Int>
  {
    if (path != null && path.length > 0)
      {
        var last = path.length -1;
        for (i in 1...last)
          if ( segmentsIntersect( path[i-1], path[i], path[last], pt) )
            return i;
      }
    return null;
  }

  // useful for "shrinking" a path so that, when drawn via a Graphics
  // object, the Sprite will remain small. 
  public static function translatePathToOrigin (path:Array<Point>) : Array<Point>
  {
    if (path.length == 0) return [];

    var minX = path[0].x;
    var minY = path[0].y;

    for (pt in path)
      {
        minX = Math.min( minX, pt.x);
        minY = Math.min( minY, pt.y);
      }

    // non-destructive w/rspct to path
    return path.map( pt -> new Point(pt.x - minX, pt.y - minY)); 
  }
  
}

class Main extends Sprite
{
  public function new()
  {
    super();
    addEventListener(Event.ADDED_TO_STAGE, onInit);
  }

  function onInit (e)
  {
    var screen = new DrawingScreen();
    addChild( screen );
  }
  
}
