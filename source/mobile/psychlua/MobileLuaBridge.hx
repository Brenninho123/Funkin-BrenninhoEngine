package mobile.psychlua;

class MobileLuaBridge
{
	public static function implement(funk:psychlua.FunkinLua):Void
	{
		#if (mobile && LUA_ALLOWED)
		mobile.psychlua.MobileFunctions.implement(funk);
		#if android
		mobile.psychlua.AndroidFunctions.implement(funk);
		#end
		#end
	}
}