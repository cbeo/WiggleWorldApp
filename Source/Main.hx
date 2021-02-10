package;

import openfl.display.Sprite;
import openfl.geom.Point;
import openfl.events.MouseEvent;
import openfl.events.KeyboardEvent;
import openfl.events.Event;
import openfl.events.TimerEvent;
import openfl.ui.Keyboard;
import openfl.utils.Timer;
import openfl.display.SimpleButton;
import openfl.text.TextField;
import openfl.text.TextFormat;
import motion.Actuate;
import haxe.ds.Option;

using Lambda;

typedef PointType = { x:Float, y:Float};
typedef HasVelocity =  {velocity: PointType};
typedef Circle = PointType & {radius:Float};
typedef HasColor = {color: Int};

typedef MovingColoredCircle = Circle & HasVelocity & HasColor;


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
  var path:Array<Point> = [];
  var circles:Array<MovingColoredCircle> = [];

  public function new (path:Array<Point>)
  {
    super();
    this.path = path;
  }
}

class DrawingScreen extends Sprite
{

  /* the prupose of which is to produce a path of a closed polygon
     suitable for passing in as the "skin" of a wiggler. */
  
  var path: Array<Point> = [];
  var holdPath:Bool = false;

  public function new ()
  {
    super();
    addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
    addEventListener(MouseEvent.MOUSE_UP, onMouseUp);
    addEventListener(MouseEvent.MOUSE_OUT, onMouseOut);
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
    trace('onMouseDown');
    refresh();
    drawing = true;
    timestamp = haxe.Timer.stamp();
    path = [ new Point(e.localX, e.localY) ];

    graphics.lineStyle(3, 0);
    graphics.moveTo( path[0].x, path[0].y );
  }

  function refresh ()
  {
    Actuate.stop(this);
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
  
  function onMouseOut (e)
  {
    drawing = false;
  }
  
  function clearAndRenderPath()
  {
    graphics.clear();
    graphics.lineStyle(3, 0);
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
              {
                graphics.lineTo( pt.x, pt.y );
              }

            clearAndRenderPath();
            return; // to return early
          }

        timestamp = stamp;
        path.push( pt );
        graphics.lineTo( pt.x, pt.y);
      }
  }
}

enum Line {
  Vertical(xVal:Float);
  Horizontal(yVal:Float);
  Sloped(slop:Float,yIntercept:Float);
}

class GeomTools
{

  public static function lineOfSegment ( a:Point, b:Point ): Null<Line>
  {
    if (a.equals( b )) return null;
    if (a.x == b.x) return Vertical(a.x);
    if (a.y == b.y) return Horizontal(a.y);

    var slope = (b.y - a.y) / (b.x - a.x);
    var yIntercept = a.y - slope * a.x;
    return Sloped(slope, yIntercept);
  }

  public static function isCounterClockwiseOrder(a:Point,b:Point,c:Point):Bool {
    return (b.x - a.x) * (c.y - a.y) > (b.y - a.y) * (c.x - a.x);
  }

  public static function segmentsIntersect(a:Point,b:Point,c:Point,d:Point):Bool
  {
    return (isCounterClockwiseOrder( a, c, d) != isCounterClockwiseOrder(b, c, d)) &&
      (isCounterClockwiseOrder( a ,b, c) != isCounterClockwiseOrder(a, b, d));
  }


  public static function pathIsCounterClockwise( path: Array<Point> ) : Bool
  {
    return path.length > 2 && isCounterClockwiseOrder(path[0], path[1], path[2]);
  }


  public static function linesIntersectAt(a:Point,b:Point,c:Point,d:Point):Null<Point>
  {
    var segments = [lineOfSegment(a, b), lineOfSegment(c, d)];
    trace(segments);

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
