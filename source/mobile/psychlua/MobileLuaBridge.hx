package mobile.psychlua;

#if (mobile && LUA_ALLOWED)
import mobile.psychlua.MobileFunctions;
#if android
import mobile.psychlua.AndroidFunctions;
#end
#end

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