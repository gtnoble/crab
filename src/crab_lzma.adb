with Ada.Unchecked_Conversion;
with Ada.Unchecked_Deallocation;
with Interfaces.C;

package body Crab_LZMA is

   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_long;
   use type Interfaces.C.size_t;

   --  ==================================================================
   --  lzma_stream_t mirror (x86_64 Linux, 136 bytes)
   --  ==================================================================

   type lzma_stream_t is record
      next_in        : System.Address;
      avail_in       : Interfaces.C.size_t;
      total_in       : Interfaces.C.unsigned_long;
      next_out       : System.Address;
      avail_out      : Interfaces.C.size_t;
      total_out      : Interfaces.C.unsigned_long;
      allocator      : System.Address;
      internal       : System.Address;
      reserved_ptr1  : System.Address;
      reserved_ptr2  : System.Address;
      reserved_ptr3  : System.Address;
      reserved_ptr4  : System.Address;
      reserved_int1  : Interfaces.C.unsigned_long;
      reserved_int2  : Interfaces.C.unsigned_long;
      reserved_int3  : Interfaces.C.size_t;
      reserved_int4  : Interfaces.C.size_t;
      reserved_enum1 : Interfaces.C.int;
      reserved_enum2 : Interfaces.C.int;
   end record;
   pragma Convention (C, lzma_stream_t);

   type lzma_stream_Access is access all lzma_stream_t;

   --  ==================================================================
   --  lzma_options_lzma mirror (x86_64 Linux, 112 bytes)
   --  ==================================================================

   type lzma_options_lzma is record
      dict_size        : Interfaces.C.unsigned;
      preset_dict      : System.Address;
      preset_dict_size : Interfaces.C.size_t;
      lc               : Interfaces.C.unsigned;
      lp               : Interfaces.C.unsigned;
      pb               : Interfaces.C.unsigned;
      mode             : Interfaces.C.int;
      nice_len         : Interfaces.C.unsigned;
      mf               : Interfaces.C.int;
      depth            : Interfaces.C.unsigned;
      reserved_ptr1    : System.Address;
      reserved_ptr2    : System.Address;
      reserved_ptr3    : System.Address;
      reserved_ptr4    : System.Address;
      reserved_int1    : Interfaces.C.unsigned;
      reserved_int2    : Interfaces.C.unsigned;
      reserved_int3    : Interfaces.C.unsigned;
      reserved_int4    : Interfaces.C.unsigned;
      reserved_int5    : Interfaces.C.unsigned;
      reserved_int6    : Interfaces.C.unsigned;
      reserved_int7    : Interfaces.C.unsigned;
      reserved_int8    : Interfaces.C.unsigned;
      reserved_enum1   : Interfaces.C.int;
      reserved_enum2   : Interfaces.C.int;
      reserved_enum3   : Interfaces.C.int;
      reserved_enum4   : Interfaces.C.int;
   end record;
   pragma Convention (C, lzma_options_lzma);

   type lzma_options_lzma_Access is access all lzma_options_lzma;

   --  ==================================================================
   --  lzma_filter mirror (x86_64 Linux, 16 bytes)
   --  ==================================================================

   type lzma_filter is record
      id      : Interfaces.C.unsigned_long;
      options : System.Address;
   end record;
   pragma Convention (C, lzma_filter);

   type lzma_filter_Array is array (Natural range <>) of
     aliased lzma_filter;

   --  ==================================================================
   --  LZMA constants
   --  ==================================================================

   LZMA_FILTER_LZMA2 : constant := 16#21#;
   LZMA_VLI_UNKNOWN  : constant Interfaces.C.unsigned_long :=
     Interfaces.C.unsigned_long'Last;

   LZMA_CHECK_CRC64 : constant := 4;
   LZMA_FINISH      : constant Interfaces.C.int := 3;
   LZMA_OK          : constant Interfaces.C.int := 0;
   LZMA_STREAM_END  : constant Interfaces.C.int := 1;

   --  ==================================================================
   --  C imports
   --  ==================================================================

   function c_lzma_lzma_preset
     (options : System.Address;
      preset  : Interfaces.C.unsigned) return Interfaces.C.int
     with Import, Convention => C, External_Name => "lzma_lzma_preset";

   function c_lzma_stream_encoder
     (strm    : System.Address;
      filters : System.Address;
      check   : Interfaces.C.unsigned) return Interfaces.C.int
     with Import, Convention => C, External_Name => "lzma_stream_encoder";

   function c_lzma_code
     (strm   : System.Address;
      action : Interfaces.C.int) return Interfaces.C.int
     with Import, Convention => C, External_Name => "lzma_code";

   function c_lzma_end
     (strm : System.Address) return Interfaces.C.int
     with Import, Convention => C, External_Name => "lzma_end";

   function c_lzma_stream_buffer_bound
     (uncompressed_size : Interfaces.C.size_t) return Interfaces.C.size_t
     with Import, Convention => C,
          External_Name => "lzma_stream_buffer_bound";

   --  ==================================================================
   --  Unchecked conversions and deallocation
   --  ==================================================================

   function To_Access is
     new Ada.Unchecked_Conversion (System.Address, lzma_stream_Access);

   procedure Free_lzma_stream is
     new Ada.Unchecked_Deallocation (lzma_stream_t, lzma_stream_Access);

   procedure Free_lzma_options is
     new Ada.Unchecked_Deallocation
       (lzma_options_lzma, lzma_options_lzma_Access);

   --  ==================================================================

   function Compress_Bound (Input_Size : Natural) return Natural is
   begin
      return Natural
        (c_lzma_stream_buffer_bound
           (Interfaces.C.size_t (Input_Size)));
   end Compress_Bound;

   --  ==================================================================

   function Init_Stream
     (Level     : Integer;
      Dict_Size : Natural;
      Dict      : String := "") return LZMA_Ctx
   is
      Raw     : lzma_stream_Access := new lzma_stream_t;
      Opts    : lzma_options_lzma_Access := new lzma_options_lzma;
      Filters : lzma_filter_Array (1 .. 2);
      Rc      : Interfaces.C.int;
   begin
      Raw.all := (others => <>);

      --  Fill options with defaults for the given preset level
      Rc := c_lzma_lzma_preset
        (Opts.all'Address,
         Interfaces.C.unsigned (Level));
      if Rc /= LZMA_OK then
         Free_lzma_stream (Raw);
         Free_lzma_options (Opts);
         raise LZMA_Error;
      end if;

      --  Override dictionary size
      Opts.dict_size := Interfaces.C.unsigned (Dict_Size);

      --  Set preset dictionary for match-finding
      --  The probability model starts fresh — this avoids model
      --  corruption that causes the "highly negative MI" problem.
      if Dict'Length > 0 then
         Opts.preset_dict := Dict'Address;
         Opts.preset_dict_size := Interfaces.C.size_t (Dict'Length);
      end if;

      --  Build filter chain: [LZMA2, terminator]
      Filters (1) :=
        (id      => LZMA_FILTER_LZMA2,
         options => Opts.all'Address);
      Filters (2) :=
        (id      => LZMA_VLI_UNKNOWN,
         options => System.Null_Address);

      --  Initialise the stream encoder with our filter chain
      Rc := c_lzma_stream_encoder
        (Raw.all'Address,
         Filters (1)'Address,
         LZMA_CHECK_CRC64);
      Free_lzma_options (Opts);

      if Rc /= LZMA_OK then
         Free_lzma_stream (Raw);
         raise LZMA_Error;
      end if;

      return (Handle => Raw.all'Address);
   end Init_Stream;

   --  ==================================================================

   procedure Load_Dict (S : in out LZMA_Ctx; Dict : String) is
      pragma Unreferenced (S);
      pragma Unreferenced (Dict);
   begin
      --  No-op: dictionary is now specified at Init_Stream time
      --  via the preset_dict mechanism.  This avoids corrupting
      --  the probability model by encoding the dict through the stream.
      null;
   end Load_Dict;

   --  ==================================================================

   procedure Compress_Stream
     (S        : in out LZMA_Ctx;
      Source   : String;
      Dest     : in out Crab_Zlib.Byte_Array;
      Dest_Len : out Natural)
   is
      Ptr : constant lzma_stream_Access := To_Access (S.Handle);
      Rc  : Interfaces.C.int;
   begin
      Ptr.next_in   := Source'Address;
      Ptr.avail_in  := Interfaces.C.size_t (Source'Length);
      Ptr.next_out  := Dest'Address;
      Ptr.avail_out := Interfaces.C.size_t (Dest'Length);
      Ptr.total_out := 0;

      Rc := c_lzma_code (Ptr.all'Address, LZMA_FINISH);
      if Rc /= LZMA_STREAM_END then
         raise LZMA_Error;
      end if;

      Dest_Len := Natural (Ptr.total_out);
   end Compress_Stream;

   --  ==================================================================

   procedure Free_Stream (S : in out LZMA_Ctx) is
      Ptr    : lzma_stream_Access := To_Access (S.Handle);
      Ignore : Interfaces.C.int;
   begin
      Ignore := c_lzma_end (Ptr.all'Address);
      S.Handle := System.Null_Address;
      Free_lzma_stream (Ptr);
   end Free_Stream;

   --  ==================================================================

   function Compress_Bare
     (Source    : String;
      Level     : Integer;
      Dict_Size : Natural;
      Dict      : String) return Natural
   is
      S    : LZMA_Ctx := Init_Stream (Level, Dict_Size, Dict);
      type Byte_Array_Access is access Crab_Zlib.Byte_Array;
      Buf  : Byte_Array_Access := new Crab_Zlib.Byte_Array (1 .. Compress_Bound (Source'Length));
      Dlen : Natural;
   begin
      Compress_Stream (S, Source, Buf.all, Dlen);
      Free_Stream (S);
      return Dlen;
   end Compress_Bare;

end Crab_LZMA;
