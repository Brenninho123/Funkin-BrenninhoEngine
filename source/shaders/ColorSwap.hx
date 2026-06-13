package shaders;

import flixel.system.FlxAssets.FlxShader;

class ColorSwap
{
	public var shader(default, null):ColorSwapShader = new ColorSwapShader();

	public var hue(default, set):Float         = 0;
	public var saturation(default, set):Float  = 0;
	public var brightness(default, set):Float  = 0;
	public var contrast(default, set):Float    = 0;
	public var temperature(default, set):Float = 0;
	public var outline(default, set):Bool      = false;
	public var outlineColor(default, set):Array<Float>  = [1.0, 1.0, 1.0, 1.0];
	public var outlineSize(default, set):Float = 3.0;
	public var vignette(default, set):Float    = 0.0;
	public var vignetteColor(default, set):Array<Float> = [0.0, 0.0, 0.0];

	private function set_hue(v:Float):Float
	{
		shader.uHue.value        = [hue = v]; return v;
	}
	private function set_saturation(v:Float):Float
	{
		shader.uSaturation.value = [saturation = v]; return v;
	}
	private function set_brightness(v:Float):Float
	{
		shader.uBrightness.value = [brightness = v]; return v;
	}
	private function set_contrast(v:Float):Float
	{
		shader.uContrast.value   = [contrast = v]; return v;
	}
	private function set_temperature(v:Float):Float
	{
		shader.uTemperature.value = [temperature = v]; return v;
	}
	private function set_outline(v:Bool):Bool
	{
		shader.uOutlineEnabled.value = [outline = v]; return v;
	}
	private function set_outlineColor(v:Array<Float>):Array<Float>
	{
		shader.uOutlineColor.value = v; return outlineColor = v;
	}
	private function set_outlineSize(v:Float):Float
	{
		shader.uOutlineSize.value = [outlineSize = v]; return v;
	}
	private function set_vignette(v:Float):Float
	{
		shader.uVignette.value   = [vignette = v]; return v;
	}
	private function set_vignetteColor(v:Array<Float>):Array<Float>
	{
		shader.uVignetteColor.value = v; return vignetteColor = v;
	}

	public function new()
	{
		shader.uHue.value            = [0.0];
		shader.uSaturation.value     = [0.0];
		shader.uBrightness.value     = [0.0];
		shader.uContrast.value       = [0.0];
		shader.uTemperature.value    = [0.0];
		shader.uOutlineEnabled.value = [false];
		shader.uOutlineColor.value   = [1.0, 1.0, 1.0, 1.0];
		shader.uOutlineSize.value    = [3.0];
		shader.uVignette.value       = [0.0];
		shader.uVignetteColor.value  = [0.0, 0.0, 0.0];
	}

	public function reset():Void
	{
		hue           = 0;
		saturation    = 0;
		brightness    = 0;
		contrast      = 0;
		temperature   = 0;
		outline       = false;
		outlineSize   = 3.0;
		outlineColor  = [1.0, 1.0, 1.0, 1.0];
		vignette      = 0.0;
		vignetteColor = [0.0, 0.0, 0.0];
	}
}

class ColorSwapShader extends FlxShader
{
	@:glFragmentSource('
		varying float openfl_Alphav;
		varying vec4  openfl_ColorMultiplierv;
		varying vec4  openfl_ColorOffsetv;
		varying vec2  openfl_TextureCoordv;

		uniform bool      openfl_HasColorTransform;
		uniform vec2      openfl_TextureSize;
		uniform sampler2D bitmap;

		uniform bool hasTransform;
		uniform bool hasColorTransform;

		vec4 flixel_texture2D(sampler2D bmp, vec2 coord)
		{
			vec4 color = texture2D(bmp, coord);
			if (!hasTransform) return color;
			if (color.a == 0.0) return vec4(0.0);
			if (!hasColorTransform) return color * openfl_Alphav;

			color = vec4(color.rgb / color.a, color.a);
			mat4 cm = mat4(0);
			cm[0][0] = openfl_ColorMultiplierv.x;
			cm[1][1] = openfl_ColorMultiplierv.y;
			cm[2][2] = openfl_ColorMultiplierv.z;
			cm[3][3] = openfl_ColorMultiplierv.w;
			color = clamp(openfl_ColorOffsetv + (color * cm), 0.0, 1.0);
			if (color.a > 0.0)
				return vec4(color.rgb * color.a * openfl_Alphav, color.a * openfl_Alphav);
			return vec4(0.0);
		}

		uniform float uHue;
		uniform float uSaturation;
		uniform float uBrightness;
		uniform float uContrast;
		uniform float uTemperature;
		uniform bool  uOutlineEnabled;
		uniform vec4  uOutlineColor;
		uniform float uOutlineSize;
		uniform float uVignette;
		uniform vec3  uVignetteColor;

		vec3 rgb2hsv(vec3 c)
		{
			vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
			vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
			vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
			float d = q.x - min(q.w, q.y);
			float e = 1.0e-10;
			return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
		}

		vec3 hsv2rgb(vec3 c)
		{
			vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
			vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
			return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
		}

		void main()
		{
			vec4 color = flixel_texture2D(bitmap, openfl_TextureCoordv);
			if (color.a == 0.0) { gl_FragColor = vec4(0.0); return; }

			vec3 rgb = color.rgb / color.a;

			if (uTemperature != 0.0)
			{
				rgb.r += uTemperature * 0.1;
				rgb.b -= uTemperature * 0.1;
				rgb    = clamp(rgb, 0.0, 1.0);
			}

			vec3 hsv = rgb2hsv(rgb);
			hsv.x    = fract(hsv.x + uHue);
			hsv.y    = clamp(hsv.y + uSaturation, 0.0, 1.0);
			hsv.z    = clamp(hsv.z * (1.0 + uBrightness), 0.0, 1.0);
			rgb      = hsv2rgb(hsv);

			if (uContrast != 0.0)
				rgb = clamp((rgb - 0.5) * (1.0 + uContrast) + 0.5, 0.0, 1.0);

			rgb  = mix(rgb, pow(max(rgb, vec3(0.0)), vec3(1.0 / 2.2)), 0.35);

			float lum = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
			rgb = mix(rgb, vec3(lum), clamp((0.18 - lum) * 1.5, 0.0, 0.25));

			color = vec4(rgb * color.a, color.a);

			if (uOutlineEnabled && color.a <= 0.5)
			{
				float w = uOutlineSize / openfl_TextureSize.x;
				float h = uOutlineSize / openfl_TextureSize.y;
				float n = flixel_texture2D(bitmap, openfl_TextureCoordv + vec2( w,  0)).a
				        + flixel_texture2D(bitmap, openfl_TextureCoordv + vec2(-w,  0)).a
				        + flixel_texture2D(bitmap, openfl_TextureCoordv + vec2( 0,  h)).a
				        + flixel_texture2D(bitmap, openfl_TextureCoordv + vec2( 0, -h)).a
				        + flixel_texture2D(bitmap, openfl_TextureCoordv + vec2( w,  h)).a
				        + flixel_texture2D(bitmap, openfl_TextureCoordv + vec2(-w, -h)).a
				        + flixel_texture2D(bitmap, openfl_TextureCoordv + vec2( w, -h)).a
				        + flixel_texture2D(bitmap, openfl_TextureCoordv + vec2(-w,  h)).a;
				if (n > 0.0) color = uOutlineColor;
			}

			if (uVignette > 0.0)
			{
				vec2  uv     = openfl_TextureCoordv * 2.0 - 1.0;
				float vd     = 1.0 - dot(uv * vec2(0.75, 1.0), uv * vec2(0.75, 1.0));
				float factor = mix(1.0, smoothstep(0.0, 1.0, vd), uVignette);
				color.rgb    = mix(uVignetteColor * color.a, color.rgb, factor);
			}

			gl_FragColor = color;
		}')

	@:glVertexSource('
		attribute float openfl_Alpha;
		attribute vec4  openfl_ColorMultiplier;
		attribute vec4  openfl_ColorOffset;
		attribute vec4  openfl_Position;
		attribute vec2  openfl_TextureCoord;

		varying float openfl_Alphav;
		varying vec4  openfl_ColorMultiplierv;
		varying vec4  openfl_ColorOffsetv;
		varying vec2  openfl_TextureCoordv;

		uniform mat4 openfl_Matrix;
		uniform bool openfl_HasColorTransform;
		uniform vec2 openfl_TextureSize;

		attribute float alpha;
		attribute vec4  colorMultiplier;
		attribute vec4  colorOffset;
		uniform bool hasColorTransform;

		void main(void)
		{
			openfl_Alphav        = openfl_Alpha;
			openfl_TextureCoordv = openfl_TextureCoord;

			if (openfl_HasColorTransform)
			{
				openfl_ColorMultiplierv = openfl_ColorMultiplier;
				openfl_ColorOffsetv     = openfl_ColorOffset / 255.0;
			}

			gl_Position   = openfl_Matrix * openfl_Position;
			openfl_Alphav = openfl_Alpha * alpha;

			if (hasColorTransform)
			{
				openfl_ColorOffsetv     = colorOffset / 255.0;
				openfl_ColorMultiplierv = colorMultiplier;
			}
		}')

	public function new() { super(); }
}
