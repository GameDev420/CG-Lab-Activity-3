Shader "Custom/StylizedWater"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}

        _Smoothness("Smoothness", Float) = 0.5
        _Occlusion("Occlusion", Float) = 1.0
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        // Both required for screen space effects
        UsePass "Universal Render Pipeline/Lit/DepthNormals"
        UsePass "Universal Render Pipeline/Lit/DepthOnly"

        Pass
        {
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
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl" // Dependancy of GlobalIllumination.hlsl
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/GlobalIllumination.hlsl"

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
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float4 _BaseMap_ST;

                float _Smoothness;
                float _Occlusion;

            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float3 N = SafeNormalize(IN.normalWS);
                float3 V = SafeNormalize(GetWorldSpaceViewDir(IN.positionWS));

                float3 R = reflect(-V, N);

                float2 ssUV = GetNormalizedScreenSpaceUV(IN.positionHCS);

                // Reflection Probes
                float3 probes = GlossyEnvironmentReflection(R, IN.positionWS.xyz, _Smoothness, _Occlusion, ssUV);

                // Found via Google AI Overview and reading into its sources (like the following):
                // https://discussions.unity.com/t/preview-of-screen-space-reflections-for-urp/1721494/20
                float4 ssr = SampleScreenSpaceReflection(ssUV, IN.positionWS, PerceptualSmoothnessToPerceptualRoughness(_Smoothness));
                
                // Lerp between reflection probes and SSR based on its fade weight (i.e. if object in reflection is out of view?)
                return half4(lerp(probes, ssr.rgb, ssr.a), 1.0);
            }
            ENDHLSL
        }
    }
}
