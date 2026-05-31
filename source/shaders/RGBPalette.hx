package shaders;

import objects.Note;

class RGBPalette
{
	public var shader(default, null):RGBPaletteShader = new RGBPaletteShader();

	public var r(default, set):FlxColor;
	public var g(default, set):FlxColor;
	public var b(default, set):FlxColor;
	public var mult(default, set):Float;

	public function new(?r:FlxColor = 0xFFFF0000, ?g:FlxColor = 0xFF00FF00, ?b:FlxColor = 0xFF0000FF, ?mult:Float = 1.0)
	{
		this.r = r;
		this.g = g;
		this.b = b;
		this.mult = mult;
	}

	private function set_r(color:FlxColor):FlxColor
	{
		r = color;
		shader.r.value = [color.redFloat, color.greenFloat, color.blueFloat];
		return color;
	}

	private function set_g(color:FlxColor):FlxColor
	{
		g = color;
		shader.g.value = [color.redFloat, color.greenFloat, color.blueFloat];
		return color;
	}

	private function set_b(color:FlxColor):FlxColor
	{
		b = color;
		shader.b.value = [color.redFloat, color.greenFloat, color.blueFloat];
		return color;
	}

	private function set_mult(value:Float):Float
	{
		mult = FlxMath.bound(value, 0.0, 1.0);
		shader.mult.value = [mult];
		return mult;
	}

	public function copyFrom(other:RGBPalette):Void
	{
		r = other.r;
		g = other.g;
		b = other.b;
		mult = other.mult;
	}

	public function clone():RGBPalette
	{
		return new RGBPalette(r, g, b, mult);
	}
}

class RGBShaderReference
{
	public var r(default, set):FlxColor;
	public var g(default, set):FlxColor;
	public var b(default, set):FlxColor;
	public var mult(default, set):Float;
	public var enabled(default, set):Bool = true;
	public var allowNew:Bool = true;

	public var parent:RGBPalette;

	private var _owner:FlxSprite;
	private var _original:RGBPalette;

	public function new(owner:FlxSprite, ref:RGBPalette)
	{
		parent   = ref;
		_owner   = owner;
		_original = ref;

		owner.shader = ref.shader;

		@:bypassAccessor
		{
			r    = ref.r;
			g    = ref.g;
			b    = ref.b;
			mult = ref.mult;
		}
	}

	private function set_r(value:FlxColor):FlxColor
	{
		if (allowNew && value != _original.r)
			_cloneOriginal();
		return (r = parent.r = value);
	}

	private function set_g(value:FlxColor):FlxColor
	{
		if (allowNew && value != _original.g)
			_cloneOriginal();
		return (g = parent.g = value);
	}

	private function set_b(value:FlxColor):FlxColor
	{
		if (allowNew && value != _original.b)
			_cloneOriginal();
		return (b = parent.b = value);
	}

	private function set_mult(value:Float):Float
	{
		if (allowNew && value != _original.mult)
			_cloneOriginal();
		return (mult = parent.mult = value);
	}

	private function set_enabled(value:Bool):Bool
	{
		_owner.shader = value ? parent.shader : null;
		return (enabled = value);
	}

	public function reset():Void
	{
		parent   = _original;
		allowNew = true;
		r        = _original.r;
		g        = _original.g;
		b        = _original.b;
		mult     = _original.mult;
		_owner.shader = parent.shader;
	}

	private function _cloneOriginal():Void
	{
		if (!allowNew || _original != parent)
			return;

		allowNew = false;
		parent   = _original.clone();
		_owner.shader = parent.shader;
	}
}

class RGBPaletteShader extends FlxShader
{
	@:glFragmentHeader('
		#pragma header

		uniform vec3 r;
		uniform vec3 g;
		uniform vec3 b;
		uniform float mult;

		vec4 flixel_texture2DCustom(sampler2D bitmap, vec2 coord)
		{
			vec4 color = flixel_texture2D(bitmap, coord);

			if (!hasTransform || color.a == 0.0 || mult == 0.0)
				return color;

			vec3 blended = color.r * r + color.g * g + color.b * b;
			vec4 newColor = vec4(min(blended, vec3(1.0)), color.a);

			vec4 result = mix(color, newColor, mult);

			return result.a > 0.0 ? vec4(result.rgb, result.a) : vec4(0.0);
		}
	')

	@:glFragmentSource('
		#pragma header

		void main()
		{
			gl_FragColor = flixel_texture2DCustom(bitmap, openfl_TextureCoordv);
		}
	')

	public function new()
	{
		super();
	}
}