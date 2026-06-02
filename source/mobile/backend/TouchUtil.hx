package mobile.backend;

import flixel.FlxObject;
import flixel.input.touch.FlxTouch;

class TouchUtil
{
	public static var pressed(get, never):Bool;
	public static var justPressed(get, never):Bool;
	public static var justReleased(get, never):Bool;
	public static var released(get, never):Bool;
	public static var touch(get, never):FlxTouch;

	public static function overlaps(object:FlxObject, ?camera:FlxCamera):Bool
	{
		return _anyTouch((t:FlxTouch) -> t.overlaps(object, camera != null ? camera : object.camera));
	}

	public static function overlapsComplex(object:FlxObject, ?camera:FlxCamera):Bool
	{
		if (camera != null)
			return _anyTouch((t:FlxTouch) ->
			{
				@:privateAccess
				return object.overlapsPoint(t.getWorldPosition(camera, object._point), true, camera);
			});

		for (cam in object.cameras)
			if (_anyTouch((t:FlxTouch) ->
			{
				@:privateAccess
				return object.overlapsPoint(t.getWorldPosition(cam, object._point), true, cam);
			}))
				return true;

		return false;
	}

	public static function getFirstActive():FlxTouch
	{
		return _findTouch((t:FlxTouch) -> t.pressed) ?? FlxG.touches.getFirst();
	}

	public static function getAll(?filter:FlxTouch->Bool):Array<FlxTouch>
	{
		if (filter == null) return FlxG.touches.list.copy();
		return FlxG.touches.list.filter(filter);
	}

	public static function count(?filter:FlxTouch->Bool):Int
	{
		return getAll(filter).length;
	}

	private static function _anyTouch(check:FlxTouch->Bool):Bool
	{
		for (t in FlxG.touches.list)
			if (check(t)) return true;
		return false;
	}

	private static function _findTouch(check:FlxTouch->Bool):Null<FlxTouch>
	{
		for (t in FlxG.touches.list)
			if (check(t)) return t;
		return null;
	}

	@:noCompletion private static function get_pressed():Bool      return _anyTouch((t) -> t.pressed);
	@:noCompletion private static function get_justPressed():Bool  return _anyTouch((t) -> t.justPressed);
	@:noCompletion private static function get_justReleased():Bool return _anyTouch((t) -> t.justReleased);
	@:noCompletion private static function get_released():Bool     return _anyTouch((t) -> t.released);
	@:noCompletion private static function get_touch():FlxTouch    return _findTouch((t) -> t != null) ?? FlxG.touches.getFirst();
}