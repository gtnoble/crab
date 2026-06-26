with Interfaces.C;

package body Crab_LZ4 is

   use type Interfaces.C.int;

   --  Internal C-oriented byte array for FFI overlay
   subtype C_Byte is Interfaces.C.unsigned_char;
   type C_Byte_Array is array (Natural range <>) of C_Byte;

   function c_createStream return System.Address
     with Import, Convention => C, External_Name => "LZ4_createStream";

   function c_loadDict
     (stream          : System.Address;
      dictionary      : System.Address;
      dictSize        : Interfaces.C.int) return Interfaces.C.int
     with Import, Convention => C, External_Name => "LZ4_loadDict";

   function c_compress_fast_continue
     (streamPtr       : System.Address;
      src             : System.Address;
      dst             : System.Address;
      srcSize         : Interfaces.C.int;
      dstCapacity     : Interfaces.C.int;
      acceleration    : Interfaces.C.int) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "LZ4_compress_fast_continue";

   procedure c_resetStream_fast
     (streamPtr : System.Address)
     with Import, Convention => C, External_Name => "LZ4_resetStream_fast";

   function c_freeStream
     (streamPtr : System.Address) return Interfaces.C.int
     with Import, Convention => C, External_Name => "LZ4_freeStream";

   function c_compressBound
     (inputSize : Interfaces.C.int) return Interfaces.C.int
     with Import, Convention => C, External_Name => "LZ4_compressBound";

   --  ==================================================================

   function Compress_Bound (Input_Size : Natural) return Natural is
   begin
      return Natural (c_compressBound (Interfaces.C.int (Input_Size)));
   end Compress_Bound;

   --  ==================================================================

   function Init_Stream return LZ4_Stream is
      Handle : constant System.Address := c_createStream;
      use type System.Address;
   begin
      if Handle = System.Null_Address then
         raise LZ4_Error;
      end if;
      return (Handle => Handle);
   end Init_Stream;

   --  ==================================================================

   procedure Load_Dict (S : in out LZ4_Stream; Dict : String) is
      Bytes : Interfaces.C.int;
   begin
      Bytes := c_loadDict
        (S.Handle, Dict'Address, Interfaces.C.int (Dict'Length));
      if Bytes < Interfaces.C.int (Dict'Length) then
         raise LZ4_Error;
      end if;
   end Load_Dict;

   --  ==================================================================

   procedure Compress_Stream
     (S            : in out LZ4_Stream;
      Source       : String;
      Dest         : in out Crab_Buffers.Byte_Buffer;
      Acceleration : Integer;
      Dest_Len     : out Natural)
   is
      Result  : Interfaces.C.int;
      C_Dest  : C_Byte_Array (Dest'Range);
      pragma Import (Ada, C_Dest);
      for C_Dest'Address use Dest'Address;
   begin
      Result := c_compress_fast_continue
        (S.Handle,
         Source'Address,
         C_Dest'Address,
         Interfaces.C.int (Source'Length),
         Interfaces.C.int (C_Dest'Length),
         Interfaces.C.int (Acceleration));
      if Result <= 0 then
         raise LZ4_Error;
      end if;
      Dest_Len := Natural (Result);

      c_resetStream_fast (S.Handle);
   end Compress_Stream;

   --  ==================================================================

   procedure Free_Stream (S : in out LZ4_Stream) is
      Rc : Interfaces.C.int;
      use type System.Address;
   begin
      Rc := c_freeStream (S.Handle);
      if Rc /= 0 then
         raise LZ4_Error;
      end if;
      S.Handle := System.Null_Address;
   end Free_Stream;

   --  ==================================================================

   function Compress_Bare
     (Source       : String;
      Acceleration : Integer;
      Dict         : String) return Natural
   is
      S    : LZ4_Stream := Init_Stream;
      type Buf_Access is access Crab_Buffers.Byte_Buffer;
      Buf  : Buf_Access := new Crab_Buffers.Byte_Buffer
        (1 .. Compress_Bound (Source'Length));
      Dlen : Natural;
   begin
      Load_Dict (S, Dict);
      Compress_Stream (S, Source, Buf.all, Acceleration, Dlen);
      Free_Stream (S);
      return Dlen;
   end Compress_Bare;

end Crab_LZ4;
