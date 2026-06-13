package scripting;

#if HSCRIPT_ALLOWED
import haxe.Json;
import hscript.Interp;
import hscript.Parser;
import hscript.Expr;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import flixel.math.FlxMath;
import flixel.sound.FlxSound;
import openfl.Assets;

typedef ScriptEvent =
{
	var name:String;
	var func:Dynamic;
}

typedef ScriptLog =
{
	var level:String;
	var message:String;
	var time:Float;
}

class HScript
{
	public static final FUNCTION_STOP:String     = 'Function_Stop';
	public static final FUNCTION_CONTINUE:String = 'Function_Continue';

	public var scriptPath:String     = '';
	public var scriptName:String     = '';
	public var active:Bool           = true;
	public var isDead:Bool           = false;

	public var logs:Array<ScriptLog>              = [];
	public var onLog:String->String->Void         = null;

	private var _interp:Interp                    = null;
	private var _parser:Parser                    = null;
	private var _expr:Expr                        = null;
	private var _vars:Map<String, Dynamic>        = new Map();
	private var _callbacks:Map<String, Array<Dynamic->Dynamic>> = new Map();

	static final MAX_LOGS:Int = 200;

	public function new(path:String)
	{
		scriptPath = path;
		scriptName = haxe.io.Path.withoutExtension(haxe.io.Path.withoutDirectory(path));

		_parser                 = new Parser();
		_parser.allowTypes      = true;
		_parser.allowMetadata   = true;
		_parser.allowJSON       = true;
		_parser.resumeErrors    = true;

		_interp = new Interp();

		_registerDefaults();
		_loadFile(path);
	}

	public static function fromString(code:String, ?name:String = 'inline'):HScript
	{
		var hs:HScript = new HScript('');
		hs.scriptPath  = '<inline>';
		hs.scriptName  = name;
		hs._loadString(code);
		return hs;
	}

	public function call(func:String, ?args:Array<Dynamic>):Dynamic
	{
		if (!active || isDead || _interp == null) return FUNCTION_CONTINUE;
		if (args == null) args = [];

		try
		{
			var fn:Dynamic = _interp.variables.get(func);
			if (fn == null) return FUNCTION_CONTINUE;
			var result:Dynamic = Reflect.callMethod(null, fn, args);
			return result ?? FUNCTION_CONTINUE;
		}
		catch (e:Dynamic)
		{
			_logError('Error in $scriptName.$func(): $e');
			return FUNCTION_CONTINUE;
		}
	}

	public function callEx(func:String, ?args:Array<Dynamic>, ?defaultVal:Dynamic):Dynamic
	{
		var result = call(func, args);
		if (result == FUNCTION_CONTINUE || result == null) return defaultVal;
		return result;
	}

	public function set(name:String, value:Dynamic):Void
	{
		if (_interp == null) return;
		_vars.set(name, value);
		_interp.variables.set(name, value);
	}

	public function get(name:String):Dynamic
	{
		if (_interp == null) return null;
		return _interp.variables.get(name);
	}

	public function exists(name:String):Bool
	{
		if (_interp == null) return false;
		return _interp.variables.exists(name);
	}

	public function setAll(vars:Map<String, Dynamic>):Void
	{
		for (key => val in vars) set(key, val);
	}

	public function execute(code:String):Dynamic
	{
		if (!active || isDead || _interp == null) return null;
		try
		{
			var expr = _parser.parseString(code);
			return _interp.execute(expr);
		}
		catch (e:Dynamic)
		{
			_logError('Execute error in $scriptName: $e');
			return null;
		}
	}

	public function on(event:String, callback:Dynamic->Dynamic):Void
	{
		if (!_callbacks.exists(event)) _callbacks.set(event, []);
		_callbacks.get(event).push(callback);
	}

	public function off(event:String):Void
	{
		_callbacks.remove(event);
	}

	public function emit(event:String, ?data:Dynamic):Dynamic
	{
		if (!_callbacks.exists(event)) return null;
		var last:Dynamic = null;
		for (cb in _callbacks.get(event))
		{
			try { last = cb(data); }
			catch (e:Dynamic) { _logError('Emit error ($event): $e'); }
		}
		return last;
	}

	public function reload():Void
	{
		if (scriptPath == '' || scriptPath == '<inline>') return;
		_interp = new Interp();
		_registerDefaults();
		for (key => val in _vars) _interp.variables.set(key, val);
		_loadFile(scriptPath);
		_logInfo('Script reloaded: $scriptName');
	}

	public function stop():Void
	{
		active  = false;
		isDead  = true;
		_callbacks.clear();
		_vars.clear();
		if (_interp != null)
		{
			_interp.variables.clear();
			_interp = null;
		}
		_parser = null;
		_expr   = null;
	}

	public function clearLogs():Void { logs = []; }

	public function getLogText():String
	{
		return logs.map((l:ScriptLog) -> '[${l.level}] ${l.message}').join('\n');
	}

	private function _loadFile(path:String):Void
	{
		if (path == null || path == '') return;
		try
		{
			#if sys
			if (!sys.FileSystem.exists(path)) { _logError('Script not found: $path'); return; }
			var content:String = sys.io.File.getContent(path);
			#else
			var content:String = Assets.getText(path);
			#end
			_loadString(content);
		}
		catch (e:Dynamic) { _logError('Failed to load $path: $e'); }
	}

	private function _loadString(code:String):Void
	{
		if (code == null || code.length == 0) return;
		try
		{
			_expr = _parser.parseString(code, scriptName);
			_interp.execute(_expr);
		}
		catch (e:Dynamic) { _logError('Parse/execute error in $scriptName: $e'); }
	}

	private function _registerDefaults():Void
	{
		var i = _interp;

		i.variables.set('Math',        Math);
		i.variables.set('Std',         Std);
		i.variables.set('String',      String);
		i.variables.set('StringTools', StringTools);
		i.variables.set('Type',        Type);
		i.variables.set('Reflect',     Reflect);
		i.variables.set('Json',        Json);
		i.variables.set('Date',        Date);
		i.variables.set('DateTools',   DateTools);
		i.variables.set('EReg',        EReg);
		i.variables.set('Lambda',      Lambda);

		i.variables.set('FlxG',        FlxG);
		i.variables.set('FlxSprite',   FlxSprite);
		i.variables.set('FlxText',     FlxText);
		i.variables.set('FlxTween',    FlxTween);
		i.variables.set('FlxEase',     FlxEase);
		i.variables.set('FlxColor',    FlxColor);
		i.variables.set('FlxTimer',    FlxTimer);
		i.variables.set('FlxMath',     FlxMath);
		i.variables.set('FlxSound',    FlxSound);

		i.variables.set('Paths',       Paths);
		i.variables.set('ClientPrefs', ClientPrefs);
		i.variables.set('CoolUtil',    CoolUtil);
		i.variables.set('Conductor',   Conductor);
		i.variables.set('PlayState',   PlayState);

		#if MODS_ALLOWED
		i.variables.set('Mods',        Mods);
		#end

		i.variables.set('Function_Stop',     FUNCTION_STOP);
		i.variables.set('Function_Continue', FUNCTION_CONTINUE);
		i.variables.set('scriptName',        scriptName);
		i.variables.set('scriptPath',        scriptPath);

		i.variables.set('trace', function(v:Dynamic):Void { _logInfo(Std.string(v)); });

		i.variables.set('debugPrint', function(v:Dynamic, ?color:FlxColor):Void
		{
			var msg:String = Std.string(v);
			_logInfo(msg);
			#if debug
			var txt = new flixel.text.FlxText(4, 4, 0, '[$scriptName] $msg', 12);
			txt.color = color ?? FlxColor.WHITE;
			FlxG.state.add(txt);
			FlxTween.tween(txt, {alpha: 0, y: txt.y - 20}, 2.0, {
				ease: FlxEase.quartIn,
				onComplete: function(_) { FlxG.state.remove(txt, true); txt.destroy(); }
			});
			#end
		});

		i.variables.set('addSprite',    function(s:FlxSprite):Void  { if (FlxG.state != null) FlxG.state.add(s); });
		i.variables.set('removeSprite', function(s:FlxSprite):Void  { if (FlxG.state != null) FlxG.state.remove(s, true); });

		i.variables.set('makeSprite', function(?x:Float = 0, ?y:Float = 0, ?image:String = null):FlxSprite
		{
			var spr = new FlxSprite(x, y);
			if (image != null) spr.loadGraphic(Paths.image(image));
			return spr;
		});

		i.variables.set('makeText', function(x:Float, y:Float, width:Float, text:String, ?size:Int = 16):FlxText
		{
			return new FlxText(x, y, width, text, size);
		});

		i.variables.set('playSound', function(key:String, ?vol:Float = 1.0):Void { FlxG.sound.play(Paths.sound(key), vol); });
		i.variables.set('playMusic', function(key:String, ?vol:Float = 1.0):Void { FlxG.sound.playMusic(Paths.music(key), vol); });
		i.variables.set('getImage',  function(key:String, ?library:String):Dynamic { return Paths.image(key, library); });

		i.variables.set('tween', function(obj:Dynamic, vals:Dynamic, dur:Float, ?ease:String = 'linear'):FlxTween
		{
			return FlxTween.tween(obj, vals, dur, {ease: _resolveEase(ease)});
		});

		i.variables.set('tweenColor', function(obj:Dynamic, dur:Float, from:FlxColor, to:FlxColor, ?ease:String = 'linear', ?onUpdate:Dynamic):Void
		{
			FlxTween.color(obj, dur, from, to, {
				ease:     _resolveEase(ease),
				onUpdate: onUpdate != null ? function(_) { onUpdate(); } : null
			});
		});

		i.variables.set('cancelTweens', function(obj:Dynamic):Void { FlxTween.cancelTweensOf(obj); });

		i.variables.set('timer', function(secs:Float, cb:Void->Void, ?loops:Int = 1):FlxTimer
		{
			return new FlxTimer().start(secs, function(_) { cb(); }, loops);
		});

		i.variables.set('setVar', function(name:String, value:Dynamic):Void { set(name, value); });
		i.variables.set('getVar', function(name:String):Dynamic { return get(name); });

		i.variables.set('switchState', function(stateClass:String):Void
		{
			var cls:Dynamic = Type.resolveClass(stateClass);
			if (cls != null) MusicBeatState.switchState(Type.createInstance(cls, []));
			else _logError('switchState: class not found — $stateClass');
		});

		i.variables.set('openSubState', function(stateClass:String, ?args:Array<Dynamic>):Void
		{
			if (args == null) args = [];
			var cls:Dynamic = Type.resolveClass(stateClass);
			if (cls != null && Std.isOfType(FlxG.state, MusicBeatState))
				cast(FlxG.state, MusicBeatState).openSubState(Type.createInstance(cls, args));
			else _logError('openSubState: class not found — $stateClass');
		});

		i.variables.set('getProperty',   function(obj:Dynamic, field:String):Dynamic    { return Reflect.getProperty(obj, field); });
		i.variables.set('setProperty',   function(obj:Dynamic, field:String, v:Dynamic):Void { Reflect.setProperty(obj, field, v); });

		i.variables.set('callMethod', function(obj:Dynamic, method:String, ?args:Array<Dynamic>):Dynamic
		{
			if (args == null) args = [];
			var fn:Dynamic = Reflect.field(obj, method);
			if (fn == null) { _logError('callMethod: $method not found'); return null; }
			return Reflect.callMethod(obj, fn, args);
		});

		i.variables.set('createInstance', function(className:String, ?args:Array<Dynamic>):Dynamic
		{
			if (args == null) args = [];
			var cls:Dynamic = Type.resolveClass(className);
			if (cls == null) { _logError('createInstance: $className not found'); return null; }
			return Type.createInstance(cls, args);
		});

		i.variables.set('resolveClass', function(className:String):Dynamic { return Type.resolveClass(className); });
		i.variables.set('resolveEnum',  function(enumName:String):Dynamic  { return Type.resolveEnum(enumName); });

		i.variables.set('import', function(className:String):Dynamic
		{
			var cls:Dynamic = Type.resolveClass(className) ?? Type.resolveEnum(className);
			if (cls == null) { _logError('import: $className not found'); return null; }
			var parts:Array<String> = className.split('.');
			i.variables.set(parts[parts.length - 1], cls);
			return cls;
		});

		i.variables.set('isOfType', function(obj:Dynamic, className:String):Bool
		{
			var cls:Dynamic = Type.resolveClass(className);
			return cls != null && Std.isOfType(obj, cls);
		});

		i.variables.set('scriptStop',     function():String { return FUNCTION_STOP; });
		i.variables.set('scriptContinue', function():String { return FUNCTION_CONTINUE; });

		i.variables.set('log', function(msg:Dynamic, ?level:String = 'info'):Void
		{
			switch (level.toLowerCase())
			{
				case 'warn':  _logWarn(Std.string(msg));
				case 'error': _logError(Std.string(msg));
				default:      _logInfo(Std.string(msg));
			}
		});

		i.variables.set('getLogs',   function():Array<ScriptLog> { return logs.copy(); });
		i.variables.set('clearLogs', function():Void             { clearLogs(); });

		#if sys
		i.variables.set('fileExists',    function(path:String):Bool         { return sys.FileSystem.exists(path); });
		i.variables.set('readFile',      function(path:String):Null<String>
		{
			try { return sys.io.File.getContent(path); }
			catch (e:Dynamic) { _logError('readFile: $e'); return null; }
		});
		i.variables.set('writeFile',     function(path:String, content:String):Bool
		{
			try { sys.io.File.saveContent(path, content); return true; }
			catch (e:Dynamic) { _logError('writeFile: $e'); return false; }
		});
		i.variables.set('listDirectory', function(path:String):Array<String>
		{
			try { return sys.FileSystem.readDirectory(path); }
			catch (e:Dynamic) { return []; }
		});
		#end

		i.variables.set('httpGet', function(url:String, cb:String->Void, ?errCb:String->Void):Void
		{
			var http = new haxe.Http(url);
			http.onData  = cb;
			http.onError = errCb ?? function(e) { _logError('httpGet error: $e'); };
			try { http.request(false); }
			catch (e:Dynamic) { _logError('httpGet: $e'); }
		});

		i.variables.set('parseJson',     function(str:String):Dynamic
		{
			try { return Json.parse(str); }
			catch (e:Dynamic) { _logError('parseJson: $e'); return null; }
		});

		i.variables.set('stringifyJson', function(obj:Dynamic, ?pretty:Bool = false):String
		{
			try { return Json.stringify(obj, pretty ? '\t' : null); }
			catch (e:Dynamic) { _logError('stringifyJson: $e'); return '{}'; }
		});

		i.variables.set('screenWidth',  FlxG.width);
		i.variables.set('screenHeight', FlxG.height);
	}

	private function _resolveEase(name:String):Float->Float
	{
		return switch (name.toLowerCase())
		{
			case 'linear':      FlxEase.linear;
			case 'quadin':      FlxEase.quadIn;
			case 'quadout':     FlxEase.quadOut;
			case 'quadinout':   FlxEase.quadInOut;
			case 'cubicin':     FlxEase.cubeIn;
			case 'cubicout':    FlxEase.cubeOut;
			case 'cubicinout':  FlxEase.cubeInOut;
			case 'quartin':     FlxEase.quartIn;
			case 'quartout':    FlxEase.quartOut;
			case 'quartinout':  FlxEase.quartInOut;
			case 'quintin':     FlxEase.quintIn;
			case 'quintout':    FlxEase.quintOut;
			case 'quintinout':  FlxEase.quintInOut;
			case 'sinein':      FlxEase.sineIn;
			case 'sineout':     FlxEase.sineOut;
			case 'sineinout':   FlxEase.sineInOut;
			case 'expoin':      FlxEase.expoIn;
			case 'expoout':     FlxEase.expoOut;
			case 'expoinout':   FlxEase.expoInOut;
			case 'circin':      FlxEase.circIn;
			case 'circout':     FlxEase.circOut;
			case 'circinout':   FlxEase.circInOut;
			case 'elasticin':   FlxEase.elasticIn;
			case 'elasticout':  FlxEase.elasticOut;
			case 'elasticinout': FlxEase.elasticInOut;
			case 'backin':      FlxEase.backIn;
			case 'backout':     FlxEase.backOut;
			case 'backinout':   FlxEase.backInOut;
			case 'bouncein':    FlxEase.bounceIn;
			case 'bounceout':   FlxEase.bounceOut;
			case 'bounceinout': FlxEase.bounceInOut;
			default:            FlxEase.linear;
		};
	}

	private function _logInfo(msg:String):Void  { _pushLog('INFO',  msg); }
	private function _logWarn(msg:String):Void  { _pushLog('WARN',  msg); }
	private function _logError(msg:String):Void { _pushLog('ERROR', msg); }

	private function _pushLog(level:String, msg:String):Void
	{
		var entry:ScriptLog = {level: level, message: msg, time: haxe.Timer.stamp()};
		logs.push(entry);
		if (logs.length > MAX_LOGS) logs.shift();
		if (onLog != null) onLog(level, msg);
	}
}

class HScriptManager
{
	private static var _scripts:Map<String, HScript> = new Map();

	public static function load(key:String, path:String):HScript
	{
		if (_scripts.exists(key)) { _scripts.get(key).stop(); _scripts.remove(key); }
		var hs = new HScript(path);
		_scripts.set(key, hs);
		return hs;
	}

	public static function loadInline(key:String, code:String):HScript
	{
		if (_scripts.exists(key)) { _scripts.get(key).stop(); _scripts.remove(key); }
		var hs = HScript.fromString(code, key);
		_scripts.set(key, hs);
		return hs;
	}

	public static function get(key:String):Null<HScript>     { return _scripts.get(key); }
	public static function exists(key:String):Bool           { return _scripts.exists(key); }
	public static function getKeys():Array<String>           { return [for (k in _scripts.keys()) k]; }

	public static function callAll(func:String, ?args:Array<Dynamic>):Void
	{
		for (hs in _scripts) if (hs.active && !hs.isDead) hs.call(func, args);
	}

	public static function setAll(name:String, value:Dynamic):Void
	{
		for (hs in _scripts) hs.set(name, value);
	}

	public static function stop(key:String):Void
	{
		var hs = _scripts.get(key);
		if (hs != null) { hs.stop(); _scripts.remove(key); }
	}

	public static function stopAll():Void  { for (hs in _scripts) hs.stop(); _scripts.clear(); }
	public static function reload(key:String):Void { var hs = _scripts.get(key); if (hs != null) hs.reload(); }
	public static function reloadAll():Void { for (hs in _scripts) hs.reload(); }

	public static function getActiveCount():Int
	{
		var count:Int = 0;
		for (hs in _scripts) if (hs.active && !hs.isDead) count++;
		return count;
	}
}
#end
