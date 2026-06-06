package language;

import haxe.Json;

typedef LanguageData =
{
	var code:String;
	var name:String;
	var nativeName:String;
	var flag:String;
	var strings:Map<String, String>;
}

class Language
{
	static final FALLBACK_CODE:String    = 'en-US';
	static final SAVE_KEY:String         = 'language';
	static final STRINGS_PATH:String     = 'assets/data/languages/';

	public static var current(default, null):LanguageData  = null;
	public static var fallback(default, null):LanguageData = null;
	public static var onChange:String->Void                = null;

	public static final available:Array<LanguageInfo> = [
		{ code: 'en-US', name: 'English',    nativeName: 'English',    flag: '🇺🇸' },
		{ code: 'pt-BR', name: 'Portuguese', nativeName: 'Português',  flag: '🇧🇷' }
	];

	private static var _strings:Map<String, Map<String, String>> = new Map();
	private static var _initialized:Bool = false;

	public static function init(?code:String):Void
	{
		if (_initialized) return;
		_initialized = true;

		_loadBuiltIn();

		var savedCode:String = _loadSavedCode();
		var targetCode:String = code ?? savedCode ?? FALLBACK_CODE;

		_setFallback(FALLBACK_CODE);
		set(targetCode, false);
	}

	public static function set(code:String, ?save:Bool = true):Bool
	{
		if (!isAvailable(code))
		{
			if (isAvailable(FALLBACK_CODE))
				code = FALLBACK_CODE;
			else
				return false;
		}

		var info:LanguageInfo = getInfo(code);
		if (info == null) return false;

		var strings:Map<String, String> = _getStrings(code);

		current = {
			code:       code,
			name:       info.name,
			nativeName: info.nativeName,
			flag:       info.flag,
			strings:    strings
		};

		if (save) _saveCode(code);
		if (onChange != null) onChange(code);

		return true;
	}

	public static function get(key:String, ?params:Array<String>):String
	{
		var result:String = _resolve(key);

		if (params != null)
			for (i in 0...params.length)
				result = result.replace('{$i}', params[i]);

		return result;
	}

	public static function getOrDefault(key:String, fallbackStr:String, ?params:Array<String>):String
	{
		var result:String = _resolve(key);
		if (result == key) result = fallbackStr;

		if (params != null)
			for (i in 0...params.length)
				result = result.replace('{$i}', params[i]);

		return result;
	}

	public static function has(key:String):Bool
	{
		if (current != null && current.strings.exists(key)) return true;
		if (fallback != null && fallback.strings.exists(key)) return true;
		return false;
	}

	public static function isAvailable(code:String):Bool
	{
		for (info in available)
			if (info.code == code) return true;
		return false;
	}

	public static function getInfo(code:String):Null<LanguageInfo>
	{
		for (info in available)
			if (info.code == code) return info;
		return null;
	}

	public static function getCurrentCode():String
	{
		return current != null ? current.code : FALLBACK_CODE;
	}

	public static function getCurrentFlag():String
	{
		return current != null ? current.flag : '🇺🇸';
	}

	public static function getCurrentNativeName():String
	{
		return current != null ? current.nativeName : 'English';
	}

	public static function next():Void
	{
		var idx:Int = 0;
		var code:String = getCurrentCode();
		for (i in 0...available.length)
			if (available[i].code == code) { idx = i; break; }

		var nextIdx:Int = (idx + 1) % available.length;
		set(available[nextIdx].code);
	}

	public static function reload():Void
	{
		if (current == null) return;
		var code:String = current.code;
		_strings.remove(code);
		set(code, false);
	}

	private static function _resolve(key:String):String
	{
		if (current != null && current.strings.exists(key))
			return current.strings.get(key);

		if (fallback != null && fallback.strings.exists(key))
			return fallback.strings.get(key);

		return key;
	}

	private static function _setFallback(code:String):Void
	{
		var info:LanguageInfo = getInfo(code);
		if (info == null) return;

		fallback = {
			code:       code,
			name:       info.name,
			nativeName: info.nativeName,
			flag:       info.flag,
			strings:    _getStrings(code)
		};
	}

	private static function _getStrings(code:String):Map<String, String>
	{
		if (_strings.exists(code)) return _strings.get(code);

		var strings:Map<String, String> = _loadFromFile(code);
		if (strings.keys().hasNext() == false)
			strings = _getBuiltIn(code);

		_strings.set(code, strings);
		return strings;
	}

	private static function _loadFromFile(code:String):Map<String, String>
	{
		var result:Map<String, String> = new Map();
		var path:String = STRINGS_PATH + '$code.json';

		#if sys
		if (!sys.FileSystem.exists(path)) return result;
		try
		{
			var parsed:Dynamic = Json.parse(sys.io.File.getContent(path));
			for (key in Reflect.fields(parsed))
				result.set(key, Std.string(Reflect.field(parsed, key)));
		}
		catch (e:Dynamic) {}
		#else
		try
		{
			var content:String = openfl.Assets.getText(path);
			if (content == null) return result;
			var parsed:Dynamic = Json.parse(content);
			for (key in Reflect.fields(parsed))
				result.set(key, Std.string(Reflect.field(parsed, key)));
		}
		catch (e:Dynamic) {}
		#end

		return result;
	}

	private static function _loadSavedCode():Null<String>
	{
		try
		{
			var save:flixel.util.FlxSave = new flixel.util.FlxSave();
			save.bind(SAVE_KEY, CoolUtil.getSavePath());
			var code:String = save.data.languageCode;
			return code != null && code.length > 0 ? code : null;
		}
		catch (e:Dynamic) { return null; }
	}

	private static function _saveCode(code:String):Void
	{
		try
		{
			var save:flixel.util.FlxSave = new flixel.util.FlxSave();
			save.bind(SAVE_KEY, CoolUtil.getSavePath());
			save.data.languageCode = code;
			save.flush();
		}
		catch (e:Dynamic) {}
	}

	private static var _builtIn:Map<String, Map<String, String>> = new Map();

	private static function _loadBuiltIn():Void
	{
		var enUS:Map<String, String> = new Map();
		enUS.set('menu.freeplay',         'Freeplay');
		enUS.set('menu.story',            'Story Mode');
		enUS.set('menu.options',          'Options');
		enUS.set('menu.credits',          'Credits');
		enUS.set('menu.donate',           'Donate');
		enUS.set('pause.resume',          'Resume');
		enUS.set('pause.restart',         'Restart Song');
		enUS.set('pause.options',         'Options');
		enUS.set('pause.exit',            'Exit to Menu');
		enUS.set('pause.exitweek',        'Exit to Week');
		enUS.set('hud.score',             'Score');
		enUS.set('hud.misses',            'Misses');
		enUS.set('hud.rating',            'Rating');
		enUS.set('hud.accuracy',          'Accuracy');
		enUS.set('hud.botplay',           'BOTPLAY');
		enUS.set('options.title',         'Options');
		enUS.set('options.save',          'Changes saved.');
		enUS.set('options.graphics',      'Graphics');
		enUS.set('options.gameplay',      'Gameplay');
		enUS.set('options.controls',      'Controls');
		enUS.set('options.language',      'Language');
		enUS.set('options.vsync',         'VSync');
		enUS.set('options.fps',           'FPS Cap');
		enUS.set('options.antialiasing',  'Antialiasing');
		enUS.set('options.downscroll',    'Downscroll');
		enUS.set('options.middlescroll',  'Middlescroll');
		enUS.set('options.ghosttapping',  'Ghost Tapping');
		enUS.set('options.flashing',      'Flashing Lights');
		enUS.set('options.lowquality',    'Low Quality');
		enUS.set('options.showcountdown', 'Show Countdown');
		enUS.set('gameover.retry',        'Press ENTER to retry.');
		enUS.set('gameover.exit',         'Press ESCAPE to exit.');
		enUS.set('week.locked',           'LOCKED');
		enUS.set('week.complete',         'COMPLETE');
		enUS.set('editor.save',           'Saved!');
		enUS.set('editor.load',           'Loaded!');
		enUS.set('editor.back',           'Back');
		enUS.set('language.current',      'Language: {0}');
		enUS.set('warning.flashing',      'This mod contains flashing lights.');
		enUS.set('warning.accept',        'Press ENTER to disable them.');
		enUS.set('warning.ignore',        'Press ESCAPE to continue anyway.');
		enUS.set('online.connected',      'Online');
		enUS.set('online.disconnected',   'Offline');
		enUS.set('online.players',        '{0} players online');
		enUS.set('loading.loading',       'Loading...');
		enUS.set('loading.ready',         'Ready!');
		enUS.set('rating.perfect',        'Perfect!!');
		enUS.set('rating.sick',           'Sick!');
		enUS.set('rating.good',           'Good');
		enUS.set('rating.bad',            'Bad');
		enUS.set('rating.shit',           'Shit');
		_builtIn.set('en-US', enUS);

		var ptBR:Map<String, String> = new Map();
		ptBR.set('menu.freeplay',         'Freeplay');
		ptBR.set('menu.story',            'Modo História');
		ptBR.set('menu.options',          'Opções');
		ptBR.set('menu.credits',          'Créditos');
		ptBR.set('menu.donate',           'Doar');
		ptBR.set('pause.resume',          'Continuar');
		ptBR.set('pause.restart',         'Reiniciar Música');
		ptBR.set('pause.options',         'Opções');
		ptBR.set('pause.exit',            'Sair para o Menu');
		ptBR.set('pause.exitweek',        'Sair para a Semana');
		ptBR.set('hud.score',             'Pontuação');
		ptBR.set('hud.misses',            'Erros');
		ptBR.set('hud.rating',            'Avaliação');
		ptBR.set('hud.accuracy',          'Precisão');
		ptBR.set('hud.botplay',           'BOTPLAY');
		ptBR.set('options.title',         'Opções');
		ptBR.set('options.save',          'Alterações salvas.');
		ptBR.set('options.graphics',      'Gráficos');
		ptBR.set('options.gameplay',      'Jogabilidade');
		ptBR.set('options.controls',      'Controles');
		ptBR.set('options.language',      'Idioma');
		ptBR.set('options.vsync',         'VSync');
		ptBR.set('options.fps',           'Limite de FPS');
		ptBR.set('options.antialiasing',  'Antialiasing');
		ptBR.set('options.downscroll',    'Scroll para Baixo');
		ptBR.set('options.middlescroll',  'Scroll Central');
		ptBR.set('options.ghosttapping',  'Ghost Tapping');
		ptBR.set('options.flashing',      'Luzes Piscantes');
		ptBR.set('options.lowquality',    'Qualidade Baixa');
		ptBR.set('options.showcountdown', 'Mostrar Contagem');
		ptBR.set('gameover.retry',        'Pressione ENTER para tentar novamente.');
		ptBR.set('gameover.exit',         'Pressione ESCAPE para sair.');
		ptBR.set('week.locked',           'BLOQUEADO');
		ptBR.set('week.complete',         'COMPLETO');
		ptBR.set('editor.save',           'Salvo!');
		ptBR.set('editor.load',           'Carregado!');
		ptBR.set('editor.back',           'Voltar');
		ptBR.set('language.current',      'Idioma: {0}');
		ptBR.set('warning.flashing',      'Este mod contém luzes piscantes.');
		ptBR.set('warning.accept',        'Pressione ENTER para desativá-las.');
		ptBR.set('warning.ignore',        'Pressione ESCAPE para continuar assim mesmo.');
		ptBR.set('online.connected',      'Online');
		ptBR.set('online.disconnected',   'Offline');
		ptBR.set('online.players',        '{0} jogadores online');
		ptBR.set('loading.loading',       'Carregando...');
		ptBR.set('loading.ready',         'Pronto!');
		ptBR.set('rating.perfect',        'Perfeito!!');
		ptBR.set('rating.sick',           'Incrível!');
		ptBR.set('rating.good',           'Bom');
		ptBR.set('rating.bad',            'Ruim');
		ptBR.set('rating.shit',           'Péssimo');
		_builtIn.set('pt-BR', ptBR);
	}

	private static function _getBuiltIn(code:String):Map<String, String>
	{
		return _builtIn.exists(code) ? _builtIn.get(code) : new Map();
	}
}

typedef LanguageInfo =
{
	var code:String;
	var name:String;
	var nativeName:String;
	var flag:String;
}
