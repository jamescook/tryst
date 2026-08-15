require "./core"
require "./video"
require "./render"

# SDL3's textures. Reopens LibSDL; the @[Link] lives in core.cr.
lib LibSDL
  alias Texture = Void

  # SDL_PixelFormat. Only the one this shard hands out, which is what
  # every caller with a pixel buffer already has: 32-bit ARGB, one byte
  # per channel.
  PIXELFORMAT_ARGB8888 = 0x16362004_u32

  # SDL_TextureAccess, in declaration order.
  TEXTUREACCESS_STATIC    = 0
  TEXTUREACCESS_STREAMING = 1
  TEXTUREACCESS_TARGET    = 2

  fun create_texture = SDL_CreateTexture(renderer : Renderer*, format : UInt32, access : LibC::Int,
                                         w : LibC::Int, h : LibC::Int) : Texture*
  fun destroy_texture = SDL_DestroyTexture(texture : Texture*)

  # Float, even though a texture is created with integer dimensions.
  fun get_texture_size = SDL_GetTextureSize(texture : Texture*, w : Float32*, h : Float32*) : Bool

  # A null rect means the whole texture. pitch is the BYTES PER ROW of
  # the source buffer, which is not always width * 4 - a caller updating
  # part of a larger image passes that image's stride.
  fun update_texture = SDL_UpdateTexture(texture : Texture*, rect : Rect*, pixels : Void*,
                                         pitch : LibC::Int) : Bool

  # Streaming textures only. Hands back a pointer to write into and the
  # pitch of that memory, which is SDL's own and need not match the
  # texture's width - always write row by row using the pitch it gives.
  # WRITE-ONLY: what is already there is undefined.
  fun lock_texture = SDL_LockTexture(texture : Texture*, rect : Rect*, pixels : Void**,
                                     pitch : LibC::Int*) : Bool
  fun unlock_texture = SDL_UnlockTexture(texture : Texture*)

  fun set_texture_blend_mode = SDL_SetTextureBlendMode(texture : Texture*, mode : BlendMode) : Bool
  fun get_texture_blend_mode = SDL_GetTextureBlendMode(texture : Texture*, mode : BlendMode*) : Bool
  fun set_texture_alpha_mod = SDL_SetTextureAlphaMod(texture : Texture*, alpha : UInt8) : Bool
  fun set_texture_color_mod = SDL_SetTextureColorMod(texture : Texture*, r : UInt8, g : UInt8,
                                                     b : UInt8) : Bool

  # Null src or dst means the whole texture / the whole target.
  fun render_texture = SDL_RenderTexture(renderer : Renderer*, texture : Texture*,
                                         srcrect : FRect*, dstrect : FRect*) : Bool

  # A null texture puts drawing back on the window.
  fun set_render_target = SDL_SetRenderTarget(renderer : Renderer*, texture : Texture*) : Bool
  fun get_render_target = SDL_GetRenderTarget(renderer : Renderer*) : Texture*
end
