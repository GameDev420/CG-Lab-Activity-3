Shader "Custom/StylizedWater"
{
    Properties
    {
        _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        _BaseMap("Base Map", 2D) = "white" {}

        _Smoothness("Smoothness", Float) = 0.5
        _Occlusion("Occlusion", Float) = 1.0

        [Space(5.0)]
        _NearDepthColor("Near Depth Color", Color) = (1, 1, 1, 1)
        _FullDepthColor("Far Depth Color", Color) = (0.5, 0.5, 0.5, 1)
        _NearDepth("Near Depth", Float) = 5
        _FarDepth("Far Depth", Float) = 5
    }

    SubShader
    {
        Tags { "RenderType" = "TransparentCutout" "Queue" = "AlphaTest" "RenderPipeline" = "UniversalPipeline" }

        // Both required for screen space effects (afaik)
        UsePass "Universal Render Pipeline/Lit/DepthNormals"
        //UsePass "Universal Render Pipeline/Lit/DepthOnly"

        Pass
        {
            Blend SrcAlpha OneMinusSrcAlpha

            // Useful for transparency and reflections
            // Also ensures we don't accidentally sample the current fragment in the depth buffer
            // ^ it always gets the depth of the fragment behind it
            ZWrite Off

            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            // Got from Unity Forums (Reflection Probes):
            // https://discussions.unity.com/t/how-to-sample-reflection-in-urp-shader-not-graph/1675584
            #pragma shader_feature_local_fragment _ENVIRONMENTREFLECTIONS_OFF		
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION
            #if (UNITY_VERSION >= 60010000)
                #pragma multi_compile _ _CLUSTER_LIGHT_LOOP
                #pragma multi_compile_fragment _ _REFLECTION_PROBE_ATLAS
            #endif

            // Required for SSR
            #pragma multi_compile_fragment _ _SCREEN_SPACE_REFLECTION

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl" // Dependancy of GlobalIllumination.hlsl, literally won't compile without it
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/GlobalIllumination.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            //#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl" // not sure if this is needed

            struct Attributes
            {
                float2 uv : TEXCOORD0;

                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float2 uv : TEXCOORD0;
                
                float4 positionHCS : SV_POSITION;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;

                float4 screenPos : TEXCOORD3;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            TEXTURE2D_X(_BehindAlphaTestDepthTexture);
            SAMPLER(sampler_BehindAlphaTestDepthTexture);

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float4 _BaseMap_ST;

                float _Smoothness;
                float _Occlusion;

                half4 _NearDepthColor;
                half4 _FullDepthColor;
                float _NearDepth;
                float _FarDepth;

            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);

                OUT.screenPos = ComputeScreenPos(OUT.positionHCS);

                return OUT;
            }

            // Helper function for depth calculations
            // Used one of numerous functions given on forums, and converted it to HLSL
            float InverseLerp(float a, float b, float value)
            {
                return saturate((value - a) / (b - a));
            }

            half3 GetReflectionColor(float3 positionWS, float3 normalWS, float2 ssUV)
            {
                float3 N = SafeNormalize(normalWS);
                float3 V = SafeNormalize(GetWorldSpaceViewDir(positionWS));
                float3 R = reflect(-V, N);

                // Reflection Probes
                float3 probes = GlossyEnvironmentReflection(R, positionWS.xyz, _Smoothness, _Occlusion, ssUV);

                // Found via Google AI Overview and reading into its sources (like the following):
                // https://discussions.unity.com/t/preview-of-screen-space-reflections-for-urp/1721494/20
                float4 ssr = SampleScreenSpaceReflection(ssUV, positionWS, PerceptualSmoothnessToPerceptualRoughness(_Smoothness));
                
                // Lerp between reflection probes and SSR based on its fade weight (i.e. if object in reflection is out of view?)
                half3 color = lerp(probes, ssr.rgb, ssr.a);
                
                return color;
            }

            half4 ApplyDepthColor(half4 finalColor, float4 positionHCS)
            {
                // Most of the functions and definitions was found with Google AI Overview and its sources,
                // though I wrote the code myself and heavily modified that which was generated to suit my specific needs.
                // e.g. I only know the LinearEyeDepth functions from AI queries, but I use my own knowledge to decide what to do with the results
                // (calculate effective depth, inverse lerp, apply to fragment color)

                // Sample depth buffer
                // This is the first method that worked when testing various functions due to shader being in the AlphaTest queue
                float2 screenUV = positionHCS.xy / _ScaledScreenParams.xy;
                float rawSceneDepth = SampleSceneDepth(screenUV);

                // Convert to linear depth value
                float belowObjDepthWS = LinearEyeDepth(rawSceneDepth, _ZBufferParams); // World space depth
                
                // Normalized based on camera near and far plane (hence the 01).
                // We don't need it here, but keeping it for future reference.
                //float 01Depth = Linear01Depth(rawDepth, _ZBufferParams);

                // Get depth of the current fragment (water surface)
                float waterDepthWS = LinearEyeDepth(positionHCS.z, _ZBufferParams);

                float t = InverseLerp(max(_NearDepth, 0), max(_FarDepth, _NearDepth), belowObjDepthWS - waterDepthWS);

                finalColor.rgb = lerp(finalColor.rgb, _FullDepthColor, t);

                return finalColor;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                half4 finalColor = _BaseColor;

                float2 ssUV = GetNormalizedScreenSpaceUV(IN.positionHCS);

                finalColor.rgb *= GetReflectionColor(IN.positionWS, IN.normalWS, ssUV);

                finalColor = ApplyDepthColor(finalColor, IN.positionHCS, ssUV);

                return finalColor;
            }

            ENDHLSL
        }
    }
}
