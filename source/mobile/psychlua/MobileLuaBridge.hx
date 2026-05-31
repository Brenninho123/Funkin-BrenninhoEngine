package mobile.psychlua;

class MobileLuaBridge
{
	public static function implement(funk:psychlua.FunkinLua):Void
	{
		#if (mobile && LUA_ALLOWED)
		MobileFunctions.implement(funk);
		#if android
		AndroidFunctions.implement(funk);
		#end
		#end
	}
}