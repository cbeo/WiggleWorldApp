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
import openfl.geom.Matrix;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.ui.Keyboard;
import openfl.utils.Timer;

using Lambda;

typedef Pt = { x:Float, y:Float};
typedef HasVelocity =  {velocity: Pt};
typedef Circle = Pt & {radius:Float};
typedef HasColor = {color: Int, visible:Bool};
typedef ColoredCircle = HasColor & Circle;

typedef RectType = Pt & {width:Float,height:Float};

typedef SwingParams = {
 startAngle:Float,
 currentAngle:Float,
 stopAngle:Float,
 spin:Float
};

typedef SkeletonNode =
  {
  butt: Pt,                   // the shared point being considered           
  followers: Array<Pt>,       // array of points that will move in sync with this bone
  active:Bool,                // whether or not this one is moving
  startAngle:Float,          // the start angle, relative to this hinge's own hinge bone.
  stopAngle:Float,          // the stop angle
  currentAngle:Float,      // the current angle
  spin:Float              // current direction of radial motion.
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
  static inline var BRANCHING_FACTOR = 5;
  static inline var QUADRANT_COEFF = 1.2;
  static inline var DONT_DRAW_THRESHOLD_COEFF = 0.8;
  static inline var NEIGHBOR_DIST_THRESHOLD_COEFF = 1.1;
  static inline var NEIGHBOR_MIN_RADIUS_COEFF = 0.1;
  static inline var RADIUS_GRADIENT:Float = 5.0;
  static inline var RADII_SIZES:Int = 20;
  static inline var MAX_SPEED:Float = 2.0;

  public static var allWigglers:Array<Wiggler> = [];

  var path:Array<Point> = [];

  var circles:Array<ColoredCircle> = [];

  var bones:Map<Pt, Array<SkeletonNode>>;
  
  var drift : Pt;

  public function new (path:Array<Point>)
  {
    super();
    this.path = Util.translatePathToOrigin( path );
    addCircles();
    addBones();

    drift = {x: MAX_SPEED * Math.random() * Util.randomSign(),
             y: MAX_SPEED * Math.random() * Util.randomSign()};

    addEventListener(Event.ENTER_FRAME, perFrame);

    addEventListener(Event.ADDED_TO_STAGE, (e) -> Wiggler.allWigglers.push(this));
  }

  // some reusable variables for intersection
  // detection. Wiggler.intersects fills these to prevent too much GC
  // action
  var thisP0 = new Point();
  var thisP1 = new Point();
  var otherP0 = new Point();
  var otherP1 = new Point();

  function intersects( other:Wiggler )
  {
    if (this == other) return false;

    // for each segment in the path, check for intersection with each
    // segment in the othe path
    for (i in 1...path.length)
      {
        thisP0.x = path[i-1].x + this.x;
        thisP0.y = path[i-1].y + this.y;
        thisP1.x = path[i].x + this.x;
        thisP1.y = path[i].y + this.y;

        for (j in 1... other.path.length)
          {
            otherP0.x = other.path[j-1].x + other.x;
            otherP0.y = other.path[j-1].y + other.y;
            otherP1.x = other.path[j].x + other.x;
            otherP1.y = other.path[j].y + other.y;
            
            if (Util.segmentsIntersect(thisP0,thisP1, otherP0,otherP1))
              return true;
          }
        // don't forget to check the last segment of the other 
        otherP0.x = other.path[other.path.length-1].x + other.x;
        otherP0.y = other.path[other.path.length-1].y + other.y;
        otherP1.x = other.path[0].x + other.x;
        otherP1.y = other.path[0].y + other.y;

        if (Util.segmentsIntersect(thisP0,thisP1, otherP0,otherP1))
          return true;
      }

    // also don't forget to check the very last semgent of this path
    // with the other path
    thisP0.x = path[path.length-1].x + this.x;
    thisP0.y = path[path.length-1].y + this.y;
    thisP1.x = path[0].x + this.x;
    thisP1.y = path[0].y + this.y;

    for (j in 1... other.path.length)
      {
        otherP0.x = other.path[j-1].x + other.x;
        otherP0.y = other.path[j-1].y + other.y;
        otherP1.x = other.path[j].x + other.x;
        otherP1.y = other.path[j].y + other.y;
        
        if (Util.segmentsIntersect(thisP0,thisP1, otherP0,otherP1))
          return true;
      }

    // finally check the last segments of both paths
    otherP0.x = other.path[other.path.length-1].x + other.x;
    otherP0.y = other.path[other.path.length-1].y + other.y;
    otherP1.x = other.path[0].x + other.x;
    otherP1.y = other.path[0].y + other.y;
    
    return Util.segmentsIntersect(thisP0,thisP1, otherP0,otherP1);
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
    return Util.pointInsideClosedPath( circ, path) &&
      !Util.circleIntersectsPath(circ, path);
  }
  
  function circleIntersectsCircles( circ ): Bool
  {
    for (c in circles)
      if (Util.circlesIntersect( c, circ))
        return true;

    return false;
  }

  var maxRadiusHere:Float = 0;
  function addCircles()
  {
    circles = [];
    if (path.length > 2)
      {
        var bbox = Util.pathBoundingBox( path );
        var rad = RADIUS_GRADIENT * RADII_SIZES;
        var step = 1.25;
        var dontDrawLargerThan = RADII_SIZES * RADIUS_GRADIENT * DONT_DRAW_THRESHOLD_COEFF;

        while (rad > 0)
          {
            for (cx in 0...Std.int(bbox.width / (step * rad)))
              for (cy in 0...Std.int(bbox.height / (step * rad)))
                {
                  var circ = {
                  x: cx * step * rad,
                  y:cy * step * rad,
                  radius:rad,
                  color: Std.int(Math.random() * 0xFFFFFF),
                  visible: rad <= dontDrawLargerThan
                  };

                  if (isValidCircle( circ ))
                    {
                      circles.push( circ );
                      maxRadiusHere = Math.max(rad, maxRadiusHere);
                    }
                }
            rad -= RADIUS_GRADIENT;
          }
      }
  }

  function segmentIntersectsBones(p1,p2):Bool
  {
    for (hinge => nodes in bones)
      for (node in nodes)
        if (Util.segmentsIntersect(p1, p2, hinge, node.butt ))
          return true;

    return false;
  }

  function biggestCircleInQuadrant(rect:Rectangle)
  {
    var biggest:ColoredCircle = null;
    for (c in circles)
      if (Util.pointInRectangle(c,rect))
        biggest = if (biggest == null || biggest.radius < c.radius) c else biggest;

    return biggest;
  }

  function associatePtWithNearestBone<P:Pt>(pt:P)
  {
    if (bones.exists( pt )) return;

    var dist:Float = 100000;
    var nearNode:SkeletonNode = null;

    for ( hinge => nodes in bones)
      for (node in nodes)
        {
          var tmpDist = Math.min(Util.dist(pt, hinge), Util.dist(pt, node.butt));
          if (pt == node.butt)
            return;               // exit if pt is a butt
          else if ( nearNode == null )
            {
              nearNode = node;
              dist = tmpDist;
            }
          else if (tmpDist < dist)
            {
              nearNode = node;
              dist = tmpDist;
            }
        }

    if (nearNode != null)
      nearNode.followers.push( pt );
  }

  function addBones ()
  {
    var reverseBones = new Map<Pt,Pt>(); // lookup for children to parents.
    bones = new Map();
    var candidates = circles.copy();
    candidates.sort( (a,b) -> Std.int(b.radius - a.radius));
    
    var frontier = [];

    // start the frontier with the largest circle in each "quadrant"
    var bbox = Util.pathBoundingBox( path );
    var quad = new Rectangle(0,0,
                             RADIUS_GRADIENT * RADII_SIZES * QUADRANT_COEFF,
                             RADIUS_GRADIENT * RADII_SIZES * QUADRANT_COEFF );

    for (ix in 0...Math.floor( bbox.width / quad.width))
      for (iy in 0...Math.floor( bbox.height / quad.height))
        {
          quad.x = ix * quad.width;
          quad.y = iy * quad.height;
          var circ = biggestCircleInQuadrant( quad );
          if (circ != null)
            {
              frontier.push( circ );
              candidates.remove( circ );
            }
        }

    var neighborDistThreshold = RADIUS_GRADIENT * RADII_SIZES * NEIGHBOR_DIST_THRESHOLD_COEFF;

    var neighborMinRadius = RADIUS_GRADIENT * RADII_SIZES * NEIGHBOR_MIN_RADIUS_COEFF;

    // add bones
    while (frontier.length > 0)
      {
        var node = frontier.shift();
        var parentHinge:Pt =
          if (reverseBones.exists(node)) reverseBones[node] else {x:node.x + 10, y:node.y};

        var validNeighbors =
          candidates.filter( n -> n.radius >= neighborMinRadius 
                             && n.radius <= node.radius
                             && Util.dist(node,n) <= neighborDistThreshold 
                             && !Util.segmentIntersectsPath(node, n, path)
                             && !segmentIntersectsBones(node, n));

        validNeighbors.sort( (a,b) -> Std.int(Util.dist(a, node) - Util.dist(b, node)));

        var toBranch = Math.ceil(Math.random() * BRANCHING_FACTOR);
        var newNbrs = validNeighbors.slice(0, toBranch);

        bones[node] = 
          newNbrs.map( nbr -> {
              var currentAngle = Util.calcAngleBetween(node, parentHinge, nbr);
              var startAngle = currentAngle - 10*ONE_DEGREE;
              var stopAngle =currentAngle + 10 * ONE_DEGREE;
              return ({
                    butt: nbr,
                    followers: [],
                    active: false,
                    startAngle: startAngle,
                    stopAngle: stopAngle,
                    currentAngle: currentAngle,
                    spin: ONE_DEGREE * if (Util.cointoss()) -1 else 1
                    } : SkeletonNode);
            });

        for (nbr in newNbrs)
          {
            reverseBones[nbr] = node;
            candidates.remove( nbr );
            frontier.push( nbr );
          }

        candidates = candidates
          .filter( circ -> {
              for (nbr in newNbrs)
                if (Util.circleIntersectsLineSegment( circ, node, nbr))
                  return false;
              return true;
            });
      }

    // associate path points and circles with a bone
    for (pt in circles)
      associatePtWithNearestBone(pt);
    for (pt in path)
     associatePtWithNearestBone(pt);

    for (c in circles)
      if ( bones.exists(c) )
        c.visible = false;
  }


  public function render ()
  {
    if (path.length == 0) return;

    graphics.clear();

    var graphicsPath = new GraphicsPath();
    graphicsPath.moveTo( path[0].x, path[0].y);
    for (i in 1...path.length)
      graphicsPath.lineTo( path[i].x, path[i].y);

    graphics.beginFill(0xfaeeee);
    graphics.lineStyle(8.0);
    graphicsPath.lineTo( path[0].x, path[0].y);
    graphics.drawPath( graphicsPath.commands, graphicsPath.data );

    graphics.lineStyle(0.0);
    for (circ in circles)
      if (circ.visible)
        {
          graphics.beginFill( circ.color, 0.5);
          graphics.drawCircle( circ.x, circ.y, circ.radius);
        }    
    
    // for (hinge => nodes in bones)
    //   for (node in nodes)
    //     {
    //       graphics.lineStyle(1,0xff0000);
    //       graphics.moveTo(hinge.x, hinge.y);
    //       graphics.lineTo(node.butt.x, node.butt.y);
    //       graphics.lineStyle(4, Std.int(Math.random() * 0xffffff));
          //graphics.lineStyle(1,0x0000ff);
          // var mid = {x: (hinge.x + node.butt.x)/2, y:(hinge.y + node.butt.y)/2};
          // for (follower in node.followers)
          //   {
          //     graphics.moveTo( mid.x, mid.y);
          //     graphics.lineTo( follower.x, follower.y);
          //   }
    //        }
    
  }

function perFrame (e)
  {
    // each "point" has a transform matrix. Because we want the whole
    // shape to transform depending on the number of "butts" attached
    // to each joint, the animation behavior varies.

    // 1 butt: wide rotation about the joint's parent bone by , say 30 to 180 degrees

    // 2->3 butts: turn taking between the butts such that their
    // associated bones never intersect, and they move in the
    // direction of the whole wiggler's "drift" vector.
    
    // 4->5 butts: synchronized expansion and contraction about a
    // "virtual line" that extends through the "bone" of hinge. A kind
    // of scissor effect.
    
    for (hinge => nodes in bones)
      for (node in nodes)
        {
          if (!Util.isBetween( node.startAngle, node.currentAngle + node.spin, node.stopAngle) ||
              boneIntersectsNeighbors(hinge, node, nodes) ||
              Util.segmentIntersectsPath(hinge, node.butt, path))
            node.spin *= -1;

          node.currentAngle += node.spin;

          Util.rotatePtAboutPivot( hinge, node.butt, node.spin);
          for (follower in node.followers)
            Util.rotatePtAboutPivot( hinge, follower, node.spin);
        }
    render();

    this.x += drift.x;
    this.y += drift.y;
    if (this.x <= 0 || this.x + this.width >= stage.stageWidth)
      drift.x *= -1;
    if (this.y <= 0 || this.y + this.height >= stage.stageHeight)
      drift.y *= -1;

    for (wiggler in Wiggler.allWigglers)
      if (wiggler != this && this.intersects( wiggler) )
          bounceOff( wiggler );
  }

  function bounceOff(other: Wiggler)
  {
    var tmp = other.drift;
    other.drift = this.drift;
    this.drift = tmp;

    this.x += drift.x;
    this.y += drift.y;
    other.x += other.drift.x;
    other.y += other.drift.y;
  }

  static inline var ONE_DEGREE: Float = 0.01745329;

  static function boneIntersectsNeighbors
  (hinge:Pt,node:SkeletonNode,nodes:Array<SkeletonNode>):Bool
  {
    for (n in nodes)
      if (n != node && Math.abs(Util.calcAngleBetween(hinge,n.butt,node.butt)) < ONE_DEGREE*2)
        return true;
    return false;                       
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
        //removeChild( candidateWiggler );
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
    graphics.clear();
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
        var intersectIndex = Util.findSelfIntersection( path, pt );
        if (intersectIndex != null)
          {
            drawing = false;
            holdPath = true;
            var intersectionPt =
              Util.linesIntersectAt( path[intersectIndex],
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

    var bbox = Util.pathBoundingBox( path );

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

class Util
{

  public static function randomSign():Int
  {
    return if ( cointoss() ) -1 else 1;
  }

  public static function cointoss():Bool
  {
    return Math.random() >= 0.5;
  }

  public static function dot<P1:Pt, P2:Pt>(p1:P1,p2:P2):Float
  {
    return p1.x * p2.x + p1.y * p2.y;
  }


  public static function calcAngleBetween
  <P1:Pt,P2:Pt,P3:Pt>
    (center:P1, p1:P2, p2:P3):Float
  {
    var v1 = {x: p1.x - center.x, y: p1.y - center.y};
    var v2 = {x: p2.x - center.x, y: p2.y - center.y};

    return Math.acos( dot(v1,v2) / Math.sqrt( dot(v1,v1) * dot(v2,v2) ));

  }

  public static function rotatePtAboutPivot
  <P1:Pt,P2:Pt>( pivot:P1, butt:P2, radians: Float)
  {
    var sine = Math.sin( radians );
    var cosine = Math.cos( radians );

    butt.x -= pivot.x;
    butt.y -= pivot.y;

    var newx = cosine * butt.x - sine * butt.y;
    var newy = sine * butt.x + cosine * butt.y;

    butt.x = newx + pivot.x;
    butt.y = newy + pivot.y;
  }



  public static function distanceToSegment
  <P1:Pt, P2:Pt, P3:Pt>
    (p:P1, a:P2, b:P3):Float
  {
    var ab = {x: b.x - a.x, y: b.y - a.y};
    var bp = {x: p.x - b.x, y: p.y - b.y};

    if ( dot( ab, bp ) > 0)
      return dist(b, p);

    var ba = {x: a.x - b.x, y: a.y - b.y};
    var pb = {x: b.x - p.x, y: b.y - p.y};

    if ( dot( ba, pb) > 0 )
      return dist(a, p);

    switch (lineOfSegment(a, b))
      {
      case Vertical( xVal ):
        return Math.abs( xVal - p.x );

      case Horizontal( yVal ):
        return Math.abs( yVal - p.y );

      case Sloped(m,intercept):
        // l1: y = m * x + intercept
        // l2: p.y = -1 * p.x / m + intercept2
        var intercept2 =  p.y + p.x / m;
        // -1 * sx / m + intercept2 = m * sx + intercept
        // intercept2 - intercept = m * sx + sx / m
        // intercept2 - intercept = sx * (m + 1/m)
        var sx = (intercept2 - intercept) / (m + 1 / m);
        var sy = m * sx + intercept;
        return dist( {x:sx,y:sy}, p);
      }

  }

  public static function pointInRectangle<P:Pt,R:RectType>(p:P,r:R):Bool
  {
    return isBetween(r.x, p.x, r.x + r.width) && isBetween(r.y, p.y, r.y + r.height);
  }

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
  public static function pointInsideClosedPath< T: Pt> (pt: T, path:Array<Point>):Bool
  {
    if (path.length < 2) return false;
    
    var intersections = 0;
    var origin : Pt = {x:0, y:0};

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
  public static function dist<P1:Pt, P2:Pt>(p1:P1,p2:P2):Float
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

  public static function circleContainsPt<C:Circle,P:Pt>
    (circ:C, pt:P):Bool
  {
    return dist(circ, pt) <= circ.radius;
  }

  public static function circleIntersectsLineSegment
  <C:Circle, P1:Pt, P2:Pt>
    ( circ: C, p1:P1, p2:P2):Bool
  {
    // if either enddpoint is in the circle, then we count an
    // intersection.  note, that this means that even if the circle
    // contains the whole segment, we count this as an intersection.
    if (circleContainsPt(circ,p1) || circleContainsPt(circ, p2))
      return true;

    switch (lineOfSegment(p1, p2))
      {
      case null:
        return false;

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

  public static function ptEquals<P1:Pt, P2:Pt>(a:P1,b:P2):Bool
  {
    return a.x == b.x && a.y == b.y;
  }

  public static function lineOfSegment<P1:Pt, P2:Pt> ( a:P1, b:P2 ): Null<Line>
  {
    if (ptEquals(a, b )) return null;
    if (a.x == b.x) return Vertical(a.x);
    if (a.y == b.y) return Horizontal(a.y);

    var slope = (b.y - a.y) / (b.x - a.x);
    var yIntercept = a.y - slope * a.x;
    return Sloped(slope, yIntercept);
  }

  public static function isCounterClockwiseOrder
  <P1:Pt,P2:Pt,P3:Pt>
  (a:P1,b:P2,c:P3):Bool {
    return (b.x - a.x) * (c.y - a.y) > (b.y - a.y) * (c.x - a.x);
  }

  public static function segmentsIntersect
  <P1:Pt,P2:Pt,P3:Pt,P4:Pt>
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
  <P1:Pt,P2:Pt,P3:Pt,P4:Pt>
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

  public static function segmentIntersectsPath
  <P1:Pt, P2:Pt, P3:Pt> 
    (p1:P1, p2:P2, path:Array<P3>) : Bool
  {
    if (path.length > 1)
      for (i in 1...path.length)
        if (segmentsIntersect( p1 , p2, path[i-1], path[i]))
          return true;

    return segmentsIntersect( p1, p2, path[path.length - 1], path[0]);    
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
