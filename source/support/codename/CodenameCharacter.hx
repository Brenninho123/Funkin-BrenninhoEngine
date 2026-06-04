package support.codename;

import haxe.xml.Access;

typedef CodenameAnimData =
{
	var name:String;
	var anim:String;
	var x:Int;
	var y:Int;
	var fps:Int;
	var loop:Bool;
}

typedef CodenameCharacterData =
{
	var sprite:String;
	var flipX:Bool;
	var isPlayer:Bool;
	var icon:String;
	var color:String;
	var x:Int;
	var y:Int;
	var anims:Array<CodenameAnimData>;
}

class CodenameCharacter
{
	public static function load(xmlPath:String):Null<CodenameCharacterData>
	{
		#if sys
		if (!sys.FileSystem.exists(xmlPath)) return null;
		try
		{
			var content:String = sys.io.File.getContent(xmlPath);
			return parse(content);
		}
		catch (e:Dynamic) { return null; }
		#else
		var content:String = openfl.Assets.getText(xmlPath);
		if (content == null) return null;
		try { return parse(content); }
		catch (e:Dynamic) { return null; }
		#end
	}

	public static function parse(xmlContent:String):Null<CodenameCharacterData>
	{
		var cleaned:String = xmlContent;

		if (cleaned.contains('<!DOCTYPE'))
		{
			var start:Int = cleaned.indexOf('<!DOCTYPE');
			var end:Int   = cleaned.indexOf('>', start);
			if (end >= 0)
				cleaned = cleaned.substr(0, start) + cleaned.substr(end + 1);
		}

		cleaned = cleaned.trim();

		var root:Xml    = Xml.parse(cleaned);
		var charNode:Xml = null;

		for (node in root)
			if (node.nodeType == Xml.Element && node.nodeName == 'character')
			{
				charNode = node;
				break;
			}

		if (charNode == null) return null;

		var data:CodenameCharacterData = {
			sprite:   charNode.exists('sprite')   ? charNode.get('sprite')            : '',
			flipX:    charNode.exists('flipX')     ? charNode.get('flipX') == 'true'   : false,
			isPlayer: charNode.exists('isPlayer')  ? charNode.get('isPlayer') == 'true': false,
			icon:     charNode.exists('icon')      ? charNode.get('icon')              : '',
			color:    charNode.exists('color')     ? charNode.get('color')             : '#FFFFFF',
			x:        charNode.exists('x')         ? Std.parseInt(charNode.get('x'))   : 0,
			y:        charNode.exists('y')         ? Std.parseInt(charNode.get('y'))   : 0,
			anims:    []
		};

		for (node in charNode)
		{
			if (node.nodeType != Xml.Element || node.nodeName != 'anim') continue;

			var anim:CodenameAnimData = {
				name: node.exists('name') ? node.get('name') : '',
				anim: node.exists('anim') ? node.get('anim') : '',
				x:    node.exists('x')    ? Std.parseInt(node.get('x')) : 0,
				y:    node.exists('y')    ? Std.parseInt(node.get('y')) : 0,
				fps:  node.exists('fps')  ? Std.parseInt(node.get('fps')) : 24,
				loop: node.exists('loop') ? node.get('loop') == 'true' : false
			};

			if (anim.name.length > 0 && anim.anim.length > 0)
				data.anims.push(anim);
		}

		return data;
	}

	public static function toCharacterJson(data:CodenameCharacterData):Dynamic
	{
		var animations:Array<Dynamic> = data.anims.map((a:CodenameAnimData) -> {
			anim:    a.anim,
			name:    a.name,
			fps:     a.fps,
			loop:    a.loop,
			offsets: [a.x, a.y],
			indices: []
		});

		return {
			animations:    animations,
			image:         data.sprite,
			scale:         1.0,
			singDuration:  4.0,
			healthIcon:    data.icon,
			healthColor:   hexToArray(data.color),
			positionArray: [data.x, data.y],
			cameraPosition:[0, 0],
			flipX:         data.flipX,
			no_antialiasing: false,
			player:        data.isPlayer
		};
	}

	public static function applyToCharacter(char:objects.Character, data:CodenameCharacterData):Void
	{
		if (char == null || data == null) return;

		for (anim in data.anims)
		{
			char.animation.addByPrefix(anim.name, anim.anim, anim.fps, anim.loop);
			char.addOffset(anim.name, anim.x, anim.y);
		}

		if (data.flipX) char.flipX = !char.flipX;
		char.x += data.x;
		char.y += data.y;
	}

	public static function findCharacterXml(name:String):Null<String>
	{
		var paths:Array<String> = [
			'assets/shared/characters/$name.xml',
			'assets/characters/$name.xml'
		];

		#if MODS_ALLOWED
		paths.insert(0, Paths.modFolders('characters/$name.xml'));
		paths.insert(0, Paths.modFolders('shared/characters/$name.xml'));
		#end

		#if sys
		for (path in paths)
			if (sys.FileSystem.exists(path))
				return path;
		#else
		for (path in paths)
			if (openfl.Assets.exists(path))
				return path;
		#end

		return null;
	}

	public static function isCodenameXml(xmlPath:String):Bool
	{
		#if sys
		if (!sys.FileSystem.exists(xmlPath)) return false;
		try
		{
			var content:String = sys.io.File.getContent(xmlPath);
			return content.contains('<!DOCTYPE codename-engine-character')
				|| (content.contains('<character') && content.contains('<anim'));
		}
		catch (e:Dynamic) { return false; }
		#else
		var content:String = openfl.Assets.getText(xmlPath);
		if (content == null) return false;
		return content.contains('<!DOCTYPE codename-engine-character')
			|| (content.contains('<character') && content.contains('<anim'));
		#end
	}

	public static function getAnimNames(data:CodenameCharacterData):Array<String>
	{
		return data.anims.map((a:CodenameAnimData) -> a.name);
	}

	public static function getAnim(data:CodenameCharacterData, name:String):Null<CodenameAnimData>
	{
		for (anim in data.anims)
			if (anim.name == name)
				return anim;
		return null;
	}

	public static function hexToArray(hex:String):Array<Int>
	{
		hex = hex.replace('#', '');
		if (hex.length == 3)
			hex = hex.charAt(0) + hex.charAt(0)
			    + hex.charAt(1) + hex.charAt(1)
			    + hex.charAt(2) + hex.charAt(2);

		return [
			Std.parseInt('0x' + hex.substr(0, 2)),
			Std.parseInt('0x' + hex.substr(2, 2)),
			Std.parseInt('0x' + hex.substr(4, 2))
		];
	}
}