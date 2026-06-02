package mobile.android;

#if android
import lime.app.Application;

typedef GameTimeData =
{
	var todayPlayTime:Int;
	var weeklyPlayTime:Int;
	var totalPlayTime:Int;
	var sessionTime:Int;
	var lastPlayed:String;
	var appPackage:String;
}

class GameTime
{
	static final SAVE_FILE:String        = "saves/gametime.json";
	static final MS_TO_MINUTES:Float     = 1.0 / 60000.0;
	static final MS_TO_HOURS:Float       = 1.0 / 3600000.0;
	static final SECONDS_PER_DAY:Int     = 86400;
	static final MAX_SESSION_HISTORY:Int = 30;

	public static var isInitialized:Bool = false;
	public static var onSessionEnd:GameTimeData->Void = null;
	public static var onDailyLimitReached:Int->Void   = null;
	public static var dailyLimitMinutes:Int            = 0;

	private static var _sessionStart:Float    = 0.0;
	private static var _todayStart:Float      = 0.0;
	private static var _todayMs:Int           = 0;
	private static var _weeklyMs:Int          = 0;
	private static var _totalMs:Int           = 0;
	private static var _sessionMs:Int         = 0;
	private static var _lastSaveDate:String   = '';
	private static var _sessionHistory:Array<Int> = [];
	private static var _limitWarned:Bool      = false;
	private static var _appPackage:String     = '';

	public static function init():Void
	{
		if (isInitialized) return;

		_appPackage  = Application.current.meta.get('packageName') ?? 'com.funkin.brenninhoengine';
		_sessionStart = Date.now().getTime();
		_todayStart   = _getDayStart();
		isInitialized = true;

		_load();
		_checkDayReset();
	}

	public static function update(elapsed:Float):Void
	{
		if (!isInitialized) return;

		var addMs:Int = Std.int(elapsed * 1000);

		_sessionMs += addMs;
		_todayMs   += addMs;
		_weeklyMs  += addMs;
		_totalMs   += addMs;

		_checkDayReset();

		if (dailyLimitMinutes > 0 && !_limitWarned)
		{
			var todayMins:Int = Std.int(_todayMs / 60000);
			if (todayMins >= dailyLimitMinutes)
			{
				_limitWarned = true;
				if (onDailyLimitReached != null) onDailyLimitReached(dailyLimitMinutes);
			}
		}
	}

	public static function endSession():Void
	{
		if (!isInitialized) return;

		_sessionHistory.push(_sessionMs);
		if (_sessionHistory.length > MAX_SESSION_HISTORY)
			_sessionHistory.shift();

		if (onSessionEnd != null) onSessionEnd(getData());

		save();
	}

	public static function getData():GameTimeData
	{
		return {
			todayPlayTime:  _todayMs,
			weeklyPlayTime: _weeklyMs,
			totalPlayTime:  _totalMs,
			sessionTime:    _sessionMs,
			lastPlayed:     DateTools.format(Date.now(), '%Y-%m-%d %H:%M:%S'),
			appPackage:     _appPackage
		};
	}

	public static function getTodayMinutes():Int
	{
		return Std.int(_todayMs * MS_TO_MINUTES);
	}

	public static function getTodayHours():Float
	{
		return Math.round(_todayMs * MS_TO_HOURS * 10) / 10;
	}

	public static function getWeeklyMinutes():Int
	{
		return Std.int(_weeklyMs * MS_TO_MINUTES);
	}

	public static function getWeeklyHours():Float
	{
		return Math.round(_weeklyMs * MS_TO_HOURS * 10) / 10;
	}

	public static function getTotalHours():Float
	{
		return Math.round(_totalMs * MS_TO_HOURS * 10) / 10;
	}

	public static function getSessionMinutes():Int
	{
		return Std.int(_sessionMs * MS_TO_MINUTES);
	}

	public static function getSessionSeconds():Int
	{
		return Std.int(_sessionMs / 1000) % 60;
	}

	public static function getSessionFormatted():String
	{
		var secs:Int  = Std.int(_sessionMs / 1000);
		var mins:Int  = Std.int(secs / 60) % 60;
		var hours:Int = Std.int(secs / 3600);
		return hours > 0 ? '${hours}h ${mins}m' : '${mins}m ${secs % 60}s';
	}

	public static function getTodayFormatted():String
	{
		var mins:Int  = getTodayMinutes();
		var hours:Int = Std.int(mins / 60);
		var rem:Int   = mins % 60;
		return hours > 0 ? '${hours}h ${rem}m' : '${mins}m';
	}

	public static function getTotalFormatted():String
	{
		var hours:Float = getTotalHours();
		return hours < 1.0 ? '${getWeeklyMinutes()}m' : '${hours}h';
	}

	public static function getAverageSessionMinutes():Float
	{
		if (_sessionHistory.length == 0) return 0.0;
		var total:Int = 0;
		for (s in _sessionHistory) total += s;
		return Math.round((total / _sessionHistory.length) * MS_TO_MINUTES * 10) / 10;
	}

	public static function getLongestSessionMinutes():Int
	{
		if (_sessionHistory.length == 0) return 0;
		var max:Int = 0;
		for (s in _sessionHistory)
			if (s > max) max = s;
		return Std.int(max * MS_TO_MINUTES);
	}

	public static function getDailyProgress():Float
	{
		if (dailyLimitMinutes <= 0) return 0.0;
		return flixel.math.FlxMath.bound(getTodayMinutes() / dailyLimitMinutes, 0.0, 1.0);
	}

	public static function getRemainingDailyMinutes():Int
	{
		if (dailyLimitMinutes <= 0) return -1;
		return Std.int(Math.max(0, dailyLimitMinutes - getTodayMinutes()));
	}

	public static function getSummary():String
	{
		return [
			'Session: ${getSessionFormatted()}',
			'Today: ${getTodayFormatted()}',
			'Weekly: ${getWeeklyHours()}h',
			'Total: ${getTotalFormatted()}',
			'Avg session: ${getAverageSessionMinutes()}m'
		].join(' • ');
	}

	public static function save():Void
	{
		if (!isInitialized) return;
		try
		{
			if (!sys.FileSystem.exists('saves'))
				sys.FileSystem.createDirectory('saves');

			sys.io.File.saveContent(SAVE_FILE, haxe.Json.stringify({
				todayMs:        _todayMs,
				weeklyMs:       _weeklyMs,
				totalMs:        _totalMs,
				lastSaveDate:   DateTools.format(Date.now(), '%Y-%m-%d'),
				sessionHistory: _sessionHistory
			}));
		}
		catch (e:Dynamic) {}
	}

	private static function _load():Void
	{
		if (!sys.FileSystem.exists(SAVE_FILE)) return;
		try
		{
			var parsed:Dynamic = haxe.Json.parse(sys.io.File.getContent(SAVE_FILE));

			_todayMs        = Reflect.field(parsed, 'todayMs')    ?? 0;
			_weeklyMs       = Reflect.field(parsed, 'weeklyMs')   ?? 0;
			_totalMs        = Reflect.field(parsed, 'totalMs')    ?? 0;
			_lastSaveDate   = Reflect.field(parsed, 'lastSaveDate') ?? '';

			var raw:Array<Dynamic> = cast Reflect.field(parsed, 'sessionHistory');
			_sessionHistory = raw != null ? raw.map((s:Dynamic) -> Std.int(s)) : [];
		}
		catch (e:Dynamic)
		{
			_todayMs = _weeklyMs = _totalMs = 0;
			_sessionHistory = [];
		}
	}

	private static function _checkDayReset():Void
	{
		var today:String = DateTools.format(Date.now(), '%Y-%m-%d');

		if (_lastSaveDate == today) return;
		if (_lastSaveDate.length == 0)
		{
			_lastSaveDate = today;
			return;
		}

		var daysDiff:Int = _getDaysDiff(_lastSaveDate, today);

		_todayMs      = 0;
		_limitWarned  = false;
		_lastSaveDate = today;

		if (daysDiff >= 7)
			_weeklyMs = 0;

		save();
	}

	private static function _getDayStart():Float
	{
		var now:Date  = Date.now();
		var day:Date  = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0);
		return day.getTime();
	}

	private static function _getDaysDiff(from:String, to:String):Int
	{
		try
		{
			var fromParts:Array<String> = from.split('-');
			var toParts:Array<String>   = to.split('-');
			var fromDate:Date = new Date(Std.parseInt(fromParts[0]), Std.parseInt(fromParts[1]) - 1, Std.parseInt(fromParts[2]), 0, 0, 0);
			var toDate:Date   = new Date(Std.parseInt(toParts[0]),   Std.parseInt(toParts[1])   - 1, Std.parseInt(toParts[2]),   0, 0, 0);
			return Std.int((toDate.getTime() - fromDate.getTime()) / (1000 * SECONDS_PER_DAY));
		}
		catch (e:Dynamic) { return 0; }
	}
}
#end
