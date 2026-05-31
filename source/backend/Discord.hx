package backend;

import lime.app.Application;
import hxdiscord_rpc.Discord;
import hxdiscord_rpc.Types;

class DiscordClient
{
	public static var isInitialized:Bool = false;

	private static final _defaultID:String = "863222024192262205";
	private static var presence:DiscordRichPresence = #if (hxdiscord_rpc > "1.2.4") new DiscordRichPresence() #else DiscordRichPresence.create() #end;

	public static var clientID(default, set):String = _defaultID;

	public static function check():Void
	{
		if (ClientPrefs.data.discordRPC)
			initialize();
		else if (isInitialized)
			shutdown();
	}

	public static function prepare():Void
	{
		if (!isInitialized && ClientPrefs.data.discordRPC)
			initialize();

		Application.current.window.onClose.add(() ->
		{
			if (isInitialized)
				shutdown();
		});
	}

	public dynamic static function shutdown():Void
	{
		Discord.Shutdown();
		isInitialized = false;
	}

	private static function onReady(request:cpp.RawConstPointer<DiscordUser>):Void
	{
		var user:cpp.Star<DiscordUser> = cpp.ConstPointer.fromRaw(request).ptr;
		var username:String = cast(user.username, String);
		var discriminator:String = cast(user.discriminator, String);

		changePresence();
	}

	private static function onError(errorCode:Int, message:cpp.ConstCharStar):Void {}

	private static function onDisconnected(errorCode:Int, message:cpp.ConstCharStar):Void {}

	public static function initialize():Void
	{
		var handlers:DiscordEventHandlers = #if (hxdiscord_rpc > "1.2.4") new DiscordEventHandlers() #else DiscordEventHandlers.create() #end;
		handlers.ready = cpp.Function.fromStaticFunction(onReady);
		handlers.disconnected = cpp.Function.fromStaticFunction(onDisconnected);
		handlers.errored = cpp.Function.fromStaticFunction(onError);

		Discord.Initialize(clientID, cpp.RawPointer.addressOf(handlers), #if (hxdiscord_rpc > "1.2.4") false #else 1 #end, null);

		sys.thread.Thread.create(() ->
		{
			var localID:String = clientID;
			while (localID == clientID)
			{
				#if DISCORD_DISABLE_IO_THREAD
				Discord.UpdateConnection();
				#end
				Discord.RunCallbacks();
				Sys.sleep(0.5);
			}
		});

		isInitialized = true;
		changePresence();
	}

	public static function changePresence(?details:String = 'Playing BrenninhoEngins\'', ?state:Null<String>, ?smallImageKey:String, ?hasStartTimestamp:Bool, ?endTimestamp:Float = 0):Void
	{
		var startTimestamp:Float = hasStartTimestamp ? Date.now().getTime() : 0;
		if (endTimestamp > 0)
			endTimestamp = startTimestamp + endTimestamp;

		presence.details = details;
		presence.state = state;
		presence.largeImageKey = 'icon';
		presence.largeImageText = 'Engine Version: ' + states.MainMenuState.psychEngineVersion;
		presence.smallImageKey = smallImageKey;
		presence.startTimestamp = Std.int(startTimestamp / 1000);
		presence.endTimestamp = Std.int(endTimestamp / 1000);

		updatePresence();
	}

	public static function updatePresence():Void
	{
		if (!isInitialized)
			return;
		Discord.UpdatePresence(cpp.RawConstPointer.addressOf(presence));
	}

	public static function resetClientID():Void
	{
		clientID = _defaultID;
	}

	private static function set_clientID(newID:String):String
	{
		var changed:Bool = (clientID != newID);
		clientID = newID;

		if (changed && isInitialized)
		{
			shutdown();
			initialize();
		}

		return newID;
	}

	#if (MODS_ALLOWED && DISCORD_ALLOWED)
	public static function loadModRPC():Void
	{
		var pack:Dynamic = Mods.getPack();
		if (pack != null && pack.discordRPC != null && pack.discordRPC != clientID)
			clientID = pack.discordRPC;
	}
	#end

	#if LUA_ALLOWED
	public static function addLuaCallbacks(lua:State):Void
	{
		Lua_helper.add_callback(lua, "changeDiscordPresence", function(details:String, state:Null<String>, ?smallImageKey:String, ?hasStartTimestamp:Bool, ?endTimestamp:Float):Void
		{
			changePresence(details, state, smallImageKey, hasStartTimestamp, endTimestamp);
		});

		Lua_helper.add_callback(lua, "changeDiscordClientID", function(?newID:String = null):Void
		{
			clientID = (newID == null) ? _defaultID : newID;
		});
	}
	#end
}