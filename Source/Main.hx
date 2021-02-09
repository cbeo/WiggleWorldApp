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
  static var upColor:Int = 0xdddddd;
  static var downAndOverColor:Int = 0xeeeeee;

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

    var over = textBox(text, downAndOverColor, textFormat, 10.0, 50, 2 );
    var up = textBox(text, upColor, textFormat, 10.0, 50, 2 );

    super( up , over, over, over);
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
  
  function onMouseDown (e) {}
  function onMouseUp (e) {}
  function onMouseOut (e) {}
  function onMouseMove (e) {}

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
