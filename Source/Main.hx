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

import haxe.ds.Option;

using Lambda;

typedef PointType = { x:Float, y:Float};
typedef HasVelocity =  {velocity: PointType};
typedef Circle = PointType & {radius:Float};
typedef HasColor = {color: Int};

typedef MovingColoredCircle = Circle & HasVelocity & HasColor;

typedef BoxConfig =
  { 
    width:Float,
    height:Float,
    bgColor:Int,               
    borderColor:Int,
    borderThickness:Float,
    borderRadius:Float,        // if set, roundRect
  };

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

  public function new ()
  {
    super();
  }

  /* Event Handling */
  
  static inline var sampleRate:Float = 0.01;
  static inline var sampleGap:Float = 5.0;

  var drawing = false;
  var timestamp:Float;

  function onMouseDown (e)
  {
    drawing = true;
    timestamp = haxe.Timer.stamp();
    path = [ new Point(e.localX, e.localY) ];
  }
  
  function onMouseUp (e)
  {
    drawing = false;
  }
  
  function onMouseOut (e)
  {
    drawing = false;
  }
  
  function onMouseMove (e)
  {
    var stamp = haxe.Timer.stamp();
    var pt = new Point( e.localX, e.localY);
    if (drawing &&
        (stamp - timestamp > sampleRate) &&
        Point.distance(pt, path[path.length - 1]) >= sampleGap)
      {
        var selfIntersection = PathTools.findSelfIntersection(path, pt);
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
    if (a.x == b.x) return Vertical(a.y);
    if (a.y == b.y) return Horizontal(a.x);

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

  public static function linesIntersectAt(a:Point,b:Point,c:Point,d:Point):Null<Point>
  {
    switch ([lineOfSegment(a, b), lineOfSegment(c, d)])
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
}

class PathTools
{
  // given a path and a point, check of the line between the last
  // point in tha path and the provided point intersects the path.  If
  // it does, the index of the path point before the
  // intersection. Otherwise return null;
  public static function findSelfIntersection
  ( path:Array<Point>, pt:Point ) : Null<Int>
  {
    if (path != null && path.length > 0)
      {
        var last = path.length -1;
        for (i in 1...last)
          if (GeomTools.segmentsIntersect( path[i-1], path[i], path[last], pt))
            return i-1;
      }
    return null;
  }
    
}

class Main extends Sprite
{
  public function new()
  {
    super();
    var b = new Button("hey");
    b.x = 100; b.y = 100;
    addChild(b);
  }

  
}
