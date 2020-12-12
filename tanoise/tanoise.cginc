// tanoise -> Extremely fast noise that does repeat, but "feels" like
// perlin noise... Ok, not perlin but smooth noise.  It can be used like
// perlin noise in many applications. Rewritten to avoid license issues.
//
//  Usage:
//    * For normal (not 1D) lookups, just use any white noise map.
//    * For 1D Output textures, you will need an offset texture map.
//    * For 4D->1D and 3D->2D Lookups, you will need to make sure SRGB on
//      your tex is OFF!
//    * For 3D->1D Lookups, it only uses the .r and .g channels of the texture.
//    * There is a possible benefit to using tanoise2,3,4 on an 1-channel
//      texture in that you could make it larger to support less repeating. 
//
//  float4 tanoise4( in float4 x )    //4 Texture Lookups
//  float tanoise4_1d( in float4 x )  //1 Texture Lookup
//  float4 tanoise3( in float3 x )    //2 Texture Lookups
//  float tanoise3_1d( in float3 x )  //1 Texture Lookup
//  float2 tanoise3_2d( in float3 x ) //1 Texture Lookup
//  float4 tanoise2( in float2 x )    //1 Texture Lookup
//
//  The texture should be the noise texture bound, standard as a 2D texture
//  to _TANoiseTex and _TANoiseTex_TexelSize should be the texel size.
//
//  Map Generation:
//    * The C rand() function is insufficient for generation of this texture.
//      (It has obvious patterns).
//    * Recommended use an LFSR.
//    * See appendix at end.
//
//  TODO: Improve matrix for non-ordinal-direction viewing.  It should be
//    possible to make the noise resistant to 90-degree angle artifacts even
//    when viewerd from other axes.
//
// The original version of this noise is restrictively licensed.  Code was
// re-written for HLSL 2020 <>< CNLohr, code henseforth may be liberally
// licensed under MIT-X11, NewBSD or Any Creative Commons License including
// CC0.
//
// This is a included in shadertrixx https://github.com/cnlohr/shadertrixx
//
// There was also a bug in the version by stubbe which caused a migration in
// x/y/z when there was an applied w value.  The matrix undoes the migration
// in this version.
//
// The absolutely key idea here is by permuting the input by a matrix, the 
// artifacts from a gridded noise source can be decimated.  At least in most
// applications!  This was loosely referenced in this page here:
//   http://devmag.org.za/2009/04/25/perlin-noise/
//
// The specific tactic for arbitrary noise was mentioned here, though this
// does not give the noise a perlinesque feel.
//   https://shadertoyunofficial.wordpress.com/2016/07/21/usual-tricks-in-shadertoyglsl/
//
// Original concepts behind this algorithm are from: 
//   https://www.shadertoy.com/view/XslGRr
// The modified version is here:
//   https://www.shadertoy.com/view/XltSWj 
//
// The original noise came with this header.
//
// Created by inigo quilez - iq/2013
// Adapted for 4d by stubbe in 2016
// License Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.
//
// Fast 3D (value) noise by using two cubic-smooth bilinear interpolations in a LUT, 
// which is much faster than its hash based (purely procedural) counterpart.
//
// Note that instead of fetching from a grey scale texture twice at an offset of (37,17)
// pixels, the green channel of the texture is a copy of the red channel offset that amount
// (thx Dave Hoskins for the suggestion to try this)
//
// Adaped by stubbe for 4d: By applying the same trick again we can copy red and green into 
// blue and alpha with an offset for w and effectively sample a 4d noise by sampling and
// blending two 3d noises.
//
//  C. Lohr notes:
// Originally, they used zOffset 37,17 and wOffset 59.0, 83.0
// This was the original matrix.
//   const mat4 m = mat4( 0.00,  0.80,  0.60, -0.4,
//                       -0.80,  0.36, -0.48, -0.5,
//                       -0.60, -0.48,  0.64,  0.2,
//                        0.40,  0.30,  0.20,  0.4);
// We have adapted this to use a pure-hexagonal move in the upper left.
// And appropriate shifts outside that.
//
// I experimentally found this combination to work better, and it seems to
// cause less repeating when applied to a sphere and a cube.  Selection of
// noise offset values is critical to avoid apparent repeating patterns.
// 

#define tanoiseWOff float2(103.0,61.0)
#define tanoiseZOff float2(51.0,111.0)

// Adjust noise axes to give it an appealing feel.  The way we do this is to
// make the outputs surface be as othogonal as possible,.  I wrote a C program
// which tried a bunch of matricies and found the best matrix for creating.
// 60 degree angles between axes.  The 60 degree mark seems to make for very
// appealing noise.

static const float4x4 tanoiseM = 
{
  -0.071301, 0.494967, -0.757557, 0.372699,
  0.494967, 0.388720, 0.303345, 0.701985,
  -0.757557, 0.303345, 0.497523, -0.290552,
  0.372699, 0.701985, -0.290552, -0.532815,
};

float4 tanoise4( in float4 x )
{
	float4 c = mul(tanoiseM,x );
	float4 p = floor(c);
	float4 f = frac(c);

	// First level smoothing for nice interpolation between levels. This
	// gets rid of the sharp artifacts that will come from the bilinear
	// interpolation.
	f = f * f * ( 3.0 - 2.0 * f );

	// Compute a u,v coordinateback in
	float2 uv = ( p.xy + p.z*tanoiseZOff +  p.w*tanoiseWOff ) + f.xy;

	// Uncomment to debug final mnoise matrix.
	fixed4 r = tex2Dlod( _TANoiseTex, float4( (uv+0.5                          )*_TANoiseTex_TexelSize, 0.0, 0.0 ) );
	fixed4 g = tex2Dlod( _TANoiseTex, float4( (uv+0.5 + tanoiseZOff             )*_TANoiseTex_TexelSize, 0.0, 0.0 ) );
	fixed4 b = tex2Dlod( _TANoiseTex, float4( (uv+0.5 + tanoiseWOff             )*_TANoiseTex_TexelSize, 0.0, 0.0 ) );
	fixed4 a = tex2Dlod( _TANoiseTex, float4( (uv+0.5 + tanoiseZOff + tanoiseWOff)*_TANoiseTex_TexelSize, 0.0, 0.0 ) );
	return lerp(lerp( r, g, f.z ), lerp(b, a, f.z), f.w);
}


//You only need one output - NOTE this must use the 1D color noise texture.
float tanoise4_1d( in float4 x )
{
	float4 c = mul(tanoiseM,x );
	float4 p = floor(c);
	float4 f = frac(c);

	// First level smoothing for nice interpolation between levels. This
	// gets rid of the sharp artifacts that will come from the bilinear
	// interpolation.
	f = f * f * ( 3.0 - 2.0 * f );

	// Compute a u,v coordinateback in
	float2 uv = ( p.xy + p.z*tanoiseZOff + p.w*tanoiseWOff ) + f.xy;

	// Uncomment to debug final mnoise matrix.
	fixed4 r = tex2Dlod( _TANoiseTex, float4( (uv+0.5)*_TANoiseTex_TexelSize, 0.0, 0.0 ) ).rgba;
	//If you absolutely want to use sRGB textures, you will need to do this step.
	//r.a = tex2Dlod( _TANoiseTex, float4( (uv+0.5 + tanoiseZOff + tanoiseWOff)*_TANoiseTex_TexelSize, 0.0, 0.0 ) );
	return lerp(lerp( r.r, r.g, f.z ), lerp(r.b, r.a, f.z), f.w);
}


float4 tanoise3( in float3 x )
{
	float3 c = mul(tanoiseM,x );
	float3 p = floor(c);
	float3 f = frac(c);

	// First level smoothing for nice interpolation between levels. This
	// gets rid of the sharp artifacts that will come from the bilinear
	// interpolation.
	f = f * f * ( 3.0 - 2.0 * f );

	// Compute a u,v coordinateback in
	float2 uv = ( p.xy + p.z*tanoiseZOff ) + f.xy;

	// Uncomment to debug final mnoise matrix.
	fixed4 r = tex2Dlod( _TANoiseTex, float4( (uv+0.5)*_TANoiseTex_TexelSize, 0.0, 0.0 ) );
	fixed4 g = tex2Dlod( _TANoiseTex, float4( (uv+0.5 + tanoiseZOff)*_TANoiseTex_TexelSize, 0.0, 0.0 ) );
	return lerp( r, g, f.z );
}

//TRICKY! If you make a map where the R/G terms are offset by exactly tanoiseZOff, you can use this function!
//You only need one output - NOTE this must use the 1D color noise texture.
float tanoise3_1d( in float3 x )
{
	float3 c = mul(tanoiseM,x );
	float3 p = floor(c);
	float3 f = frac(c);

	// First level smoothing for nice interpolation between levels. This
	// gets rid of the sharp artifacts that will come from the bilinear
	// interpolation.
	f = f * f * ( 3.0 - 2.0 * f );

	// Compute a u,v coordinateback in
	float2 uv = ( p.xy + p.z*tanoiseZOff ) + f.xy;

	// Uncomment to debug final mnoise matrix.
	fixed2 r = tex2Dlod( _TANoiseTex, float4( (uv+0.5)*_TANoiseTex_TexelSize, 0.0, 0.0 ) ).rg;
	return lerp( r.r, r.g, f.z );
}

float2 tanoise3_2d( in float3 x )
{
	float3 c = mul(tanoiseM,x );
	float3 p = floor(c);
	float3 f = frac(c);

	// First level smoothing for nice interpolation between levels. This
	// gets rid of the sharp artifacts that will come from the bilinear
	// interpolation.
	f = f * f * ( 3.0 - 2.0 * f );

	// Compute a u,v coordinateback in
	float2 uv = ( p.xy + p.z*tanoiseZOff ) + f.xy;

	// Uncomment to debug final mnoise matrix.
	fixed4 r = tex2Dlod( _TANoiseTex, float4( (uv+0.5)*_TANoiseTex_TexelSize, 0.0, 0.0 ) ).rgba;
	return lerp( r.rb, r.ga, f.z );
}


//Even for a 4D result, we only need one textuer lookup for a 2D input.
float4 tanoise2( in float2 x )
{
	float2 c = mul(tanoiseM,x );
	float2 p = floor(c);
	float2 f = frac(c);

	// First level smoothing for nice interpolation between levels. This
	// gets rid of the sharp artifacts that will come from the bilinear
	// interpolation.
	f = f * f * ( 3.0 - 2.0 * f );

	// Compute a u,v coordinateback in
	float2 uv = p.xy + f.xy;

	// Uncomment to debug final mnoise matrix.
	return tex2Dlod( _TANoiseTex, float4( (uv+0.5)*_TANoiseTex_TexelSize, 0.0, 0.0 ) );
}


/* Map Generation:
 * Example using stbi_write and c.
 * Compiles using tcc.exe generate.c -run
 *
 *  #include <stdio.h>
 *	#define STB_IMAGE_WRITE_IMPLEMENTATION
 *	#include "stb_image_write.h"
 *	
 *  //You can use other sizes. On most objects, maps as small as 64x64 are ok.
 *  //For larger non-repeating areas, use a larger texture.
 *
 *  #define NOISEBIGX 64
 *	#define NOISEBIGY 64
 *
 *  //From Wikipedia LFSR page.
 *	unsigned lfsr2(void)
 *	{
 *	    static uint32_t start_state = 0x1u;  // Any nonzero start state 
 *	    static uint32_t lfsr = 0x1u;
 *	    unsigned period = 0;
 *	
 *		unsigned lsb = lfsr & 1u;  // Get LSB (i.e., the output bit).
 *		lfsr >>= 1;                // Shift register
 *		if (lsb)                   // If the output bit is 1,
 *			lfsr ^= (1<<19)|(1<<16);       //  apply toggle mask.
 *			//Polynomial #20 on Wikipedia, period of 1,048,575 
 *		++period;
 *	
 *	    return lfsr;
 *	}
 *	uint8_t lfsru8()
 *	{
 *		uint8_t ret = 0;
 *		int i;
 *		for( i = 0; i < 8; i++ )
 *		{
 *			ret |= lfsr2() & 1;
 *			ret <<= 1;
 *		}
 *		return ret;
 *	}
 *	
 *	int main()
 *	{
 *		uint8_t NoiseBig[NOISEBIGX*NOISEBIGY][4];   //This is a regular white noise texture.
 *		uint8_t NoiseBig1D[NOISEBIGX*NOISEBIGY][4]; //This one lets you use the 1D commands.
 *	
 *		uint8_t * NoiseAll = (uint8_t*)NoiseBig;
 *		uint8_t * NoiseOffset = (uint8_t*)NoiseBig1D;
 *		int x,y;
 *		for( y = 0; y < NOISEBIGY; y++ )
 *		for( x = 0; x < NOISEBIGX; x++ )
 *		{
 *			NoiseAll[(x+y*NOISEBIGX)*4+0] = lfsru8();
 *			NoiseAll[(x+y*NOISEBIGX)*4+1] = lfsru8();
 *			NoiseAll[(x+y*NOISEBIGX)*4+2] = lfsru8();
 *			NoiseAll[(x+y*NOISEBIGX)*4+3] = lfsru8();
 *		}
 *		
 *		for( y = 0; y < NOISEBIGY; y++ )
 *		for( x = 0; x < NOISEBIGX; x++ )
 *		{
 *			NoiseOffset[(x+y*NOISEBIGX)*4+0] = NoiseAll[(((x+0     +256)%NOISEBIGX)+((y+0     +256)%NOISEBIGY)*NOISEBIGX)*4+0];
 *			NoiseOffset[(x+y*NOISEBIGX)*4+1] = NoiseAll[(((x+51    +256)%NOISEBIGX)+((y-111   +256)%NOISEBIGY)*NOISEBIGX)*4+0];
 *			NoiseOffset[(x+y*NOISEBIGX)*4+2] = NoiseAll[(((x+103   +256)%NOISEBIGX)+((y-61    +256)%NOISEBIGY)*NOISEBIGX)*4+0];
 *			NoiseOffset[(x+y*NOISEBIGX)*4+3] = NoiseAll[(((x+51+103+256)%NOISEBIGX)+((y-61-111+256)%NOISEBIGY)*NOISEBIGX)*4+0];
 *		}
 *		int l = stbi_write_png("noisebig.png", NOISEBIGX,NOISEBIGY, 4, NoiseBig, NOISEBIGX*4);
 *		l = stbi_write_png("tanoise.png", NOISEBIGX,NOISEBIGY, 4, NoiseBig1D, NOISEBIGX*4);
 *	}
 */
