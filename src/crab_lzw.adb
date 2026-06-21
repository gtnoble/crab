with Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;

package body Crab_LZW is

   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;

   --  ==================================================================
   --  Bit Writer (pack codes into byte array)
   --  Uses Unsigned_64 accumulator so code widths beyond 31 are safe.
   --  ==================================================================

   type Bit_Writer is record
      Buf_Off   : Natural := 0;
      Buf_Cap   : Natural;
      Bit_Buf   : Interfaces.Unsigned_64 := 0;
      Bit_Count : Natural := 0;
   end record;

   procedure Write_Bit_Byte
     (W    : in out Bit_Writer;
      B    : Interfaces.C.unsigned_char;
      OK   : out Boolean;
      Dest : in out Crab_Zlib.Byte_Array) is
   begin
      if W.Buf_Off >= W.Buf_Cap then
         OK := False;
         return;
      end if;
      Dest (Dest'First + W.Buf_Off) := B;
      W.Buf_Off := W.Buf_Off + 1;
      OK := True;
   end Write_Bit_Byte;

   procedure Write_Code
     (W    : in out Bit_Writer;
      Code : Natural;
      Bits : Natural;
      OK   : out Boolean;
      Dest : in out Crab_Zlib.Byte_Array)
   is
      Val : constant Interfaces.Unsigned_64 :=
        Interfaces.Unsigned_64 (Code);
   begin
      W.Bit_Buf := W.Bit_Buf or
        Interfaces.Shift_Left (Val, W.Bit_Count);
      W.Bit_Count := W.Bit_Count + Bits;
      while W.Bit_Count >= 8 loop
         Write_Bit_Byte
           (W,
            Interfaces.C.unsigned_char (W.Bit_Buf and 16#FF#),
            OK,
            Dest);
         if not OK then
            return;
         end if;
         W.Bit_Buf := Interfaces.Shift_Right (W.Bit_Buf, 8);
         W.Bit_Count := W.Bit_Count - 8;
      end loop;
      OK := True;
   end Write_Code;

   procedure Flush_Writer
     (W    : in out Bit_Writer;
      OK   : out Boolean;
      Dest : in out Crab_Zlib.Byte_Array) is
   begin
      if W.Bit_Count > 0 then
         Write_Bit_Byte
           (W,
            Interfaces.C.unsigned_char (W.Bit_Buf and 16#FF#),
            OK,
            Dest);
         W.Bit_Count := 0;
         W.Bit_Buf := 0;
      else
         OK := True;
      end if;
   end Flush_Writer;

   --  ==================================================================
   --  Bit Reader (unpack codes from byte array — for decompression)
   --  ==================================================================

   type Bit_Reader is record
      Buf_Len   : Natural;
      Buf_Off   : Natural := 0;
      Bit_Buf   : Interfaces.Unsigned_64 := 0;
      Bit_Count : Natural := 0;
   end record;

   procedure Read_Bit_Byte
     (R      : in out Bit_Reader;
      B      : out Interfaces.C.unsigned_char;
      OK     : out Boolean;
      Source : Crab_Zlib.Byte_Array) is
   begin
      if R.Buf_Off >= R.Buf_Len then
         OK := False;
         return;
      end if;
      B := Source (Source'First + R.Buf_Off);
      R.Buf_Off := R.Buf_Off + 1;
      OK := True;
   end Read_Bit_Byte;

   procedure Read_Code
     (R      : in out Bit_Reader;
      Bits   : Natural;
      Code   : out Natural;
      OK     : out Boolean;
      Source : Crab_Zlib.Byte_Array)
   is
      B  : Interfaces.C.unsigned_char;
      Rb : Boolean;
      Mask : constant Interfaces.Unsigned_64 :=
        Interfaces.Shift_Left (Interfaces.Unsigned_64'(1), Bits) - 1;
   begin
      while R.Bit_Count < Bits loop
         Read_Bit_Byte (R, B, Rb, Source);
         if not Rb then
            OK := False;
            return;
         end if;
         R.Bit_Buf := R.Bit_Buf or
           Interfaces.Shift_Left
             (Interfaces.Unsigned_64 (B), R.Bit_Count);
         R.Bit_Count := R.Bit_Count + 8;
      end loop;
      Code := Natural (R.Bit_Buf and Mask);
      R.Bit_Buf := Interfaces.Shift_Right (R.Bit_Buf, Bits);
      R.Bit_Count := R.Bit_Count - Bits;
      OK := True;
   end Read_Code;

   --  ==================================================================
   --  Hash-table operations
   --  ==================================================================

   function LZW_Hash (K : LZW_Key) return Ada.Containers.Hash_Type
   is
     (Ada.Containers.Hash_Type
        (K.Prefix * 257 + K.Suffix));

   function Lookup
     (S : LZW_Stream; Prefix : Natural; C : Natural) return Natural
   is
      use LZW_Code_Maps;
      Pos : constant Cursor := S.Code_Map.Find ((Prefix, C));
   begin
      if Pos = No_Element then
         return 0;
      else
         return Element (Pos);
      end if;
   end Lookup;

   procedure Insert
     (S : in out LZW_Stream; Prefix : Natural; C : Natural)
   is
      New_Code : constant Natural := S.Next_Code;
      New_Node : constant LZW_Node :=
        (Suffix => UC (C),
         Prefix => Prefix);
   begin
      S.Nodes.Append (New_Node);
      S.Code_Map.Insert ((Prefix, C), New_Code);
      S.Next_Code := New_Code + 1;
   end Insert;

   --  ==================================================================
   --  Initialise root nodes (single-byte codes 0..255)
   --  ==================================================================

   procedure Init_Roots (S : in out LZW_Stream) is
   begin
      S.Nodes.Clear;
      S.Code_Map.Clear;
      for I in 0 .. 255 loop
         S.Nodes.Append
           (LZW_Node'
              (Suffix => UC (I),
               Prefix => 0));
         null; -- single-byte codes are not multi-byte lookup keys
      end loop;
      S.Next_Code := 256;
      S.Code_Bits := 9;
      S.Have_Prefix := False;
   end Init_Roots;

   --  ==================================================================
   --  Public API
   --  ==================================================================

   function Compress_Bound (Input_Size : Natural) return Natural is
      --  Worst case: every input byte emits one code.
      --  Code width grows as the dictionary fills.
      --  Max code width = ceil(log2(256 + Input_Size)).
      --  Bound = ceil(Input_Size * max_code_width / 8) + 1 (flush).
      Max_Width : Natural := 9;
      Limit     : Natural := 512;  --  2^9
   begin
      while Limit < 256 + Input_Size loop
         Max_Width := Max_Width + 1;
         Limit := Limit * 2;
      end loop;
      return (Input_Size * Max_Width + 7) / 8 + 1;
   end Compress_Bound;

   --  ------------------------------------------------------------------

   function Init_Stream return LZW_Stream_Access is
      S : constant LZW_Stream_Access := new LZW_Stream;
   begin
      Init_Roots (S.all);
      return S;
   end Init_Stream;

   --  ------------------------------------------------------------------

   procedure Load_Dict (S : in out LZW_Stream; Dict : String) is
      Prefix : Natural := 0;
      Code   : Natural;
      First  : Boolean := True;
      P1     : constant Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32'(1);
   begin
      for I in Dict'Range loop
         declare
            C : constant Natural := Character'Pos (Dict (I));
         begin
            if First then
               Prefix := C;
               First := False;
            else
               Code := Lookup (S, Prefix, C);
               if Code /= 0 then
                  Prefix := Code;
               else
                  Insert (S, Prefix, C);
                  if S.Next_Code >
                    Natural
                      (Interfaces.Shift_Left
                         (P1, S.Code_Bits))
                  then
                     S.Code_Bits := S.Code_Bits + 1;
                  end if;
                  Prefix := C;
               end if;
            end if;
         end;
      end loop;

      if not First then
         S.Have_Prefix := True;
         S.Resid_Prefix := Prefix;
      end if;
   end Load_Dict;

   --  ------------------------------------------------------------------

   procedure Compress_Stream
     (S        : in out LZW_Stream;
      Source   : String;
      Dest     : in out Crab_Zlib.Byte_Array;
      Level    : Integer;
      Dest_Len : out Natural)
   is
      pragma Unreferenced (Level);

      W      : Bit_Writer := (Buf_Cap => Dest'Length, others => <>);
      OK     : Boolean;

      Prefix : Natural := 0;
      Code   : Natural;
      C      : Natural;
      P1     : constant Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32'(1);
   begin
      if S.Have_Prefix then
         Prefix := S.Resid_Prefix;
         S.Have_Prefix := False;
      end if;

      for I in Source'Range loop
         C := Character'Pos (Source (I));

         if Prefix = 0 then
            Prefix := C;
         else
            Code := Lookup (S, Prefix, C);
            if Code /= 0 then
               Prefix := Code;
            else
               Write_Code (W, Prefix, S.Code_Bits, OK, Dest);
               if not OK then
                  raise LZW_Error;
               end if;

               Insert (S, Prefix, C);
               if S.Next_Code >
                 Natural
                   (Interfaces.Shift_Left
                      (P1, S.Code_Bits))
               then
                  S.Code_Bits := S.Code_Bits + 1;
               end if;

               Prefix := C;
            end if;
         end if;
      end loop;

      if Prefix /= 0 then
         Write_Code (W, Prefix, S.Code_Bits, OK, Dest);
         if not OK then
            raise LZW_Error;
         end if;
      end if;

      Flush_Writer (W, OK, Dest);
      if not OK then
         raise LZW_Error;
      end if;

      Dest_Len := W.Buf_Off;
   end Compress_Stream;

   --  ------------------------------------------------------------------

   procedure Free_Stream_Alloc is
     new Ada.Unchecked_Deallocation (LZW_Stream, LZW_Stream_Access);

   procedure Free_Stream (S : in out LZW_Stream_Access) is
   begin
      Free_Stream_Alloc (S);
   end Free_Stream;

   --  ------------------------------------------------------------------

   function Compress_Bare
     (Source : String;
      Dict   : String) return Natural
   is
      S    : LZW_Stream_Access := Init_Stream;
      Buf  : Crab_Zlib.Byte_Array (1 .. Compress_Bound (Source'Length));
      Dlen : Natural;
   begin
      Load_Dict (S.all, Dict);
      Compress_Stream (S.all, Source, Buf, 0, Dlen);
      Free_Stream (S);
      return Dlen;
   end Compress_Bare;

   --  ==================================================================
   --  Decompression (for roundtrip testing)
   --  ==================================================================

   package Char_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Character);

   function Decompress
     (Source     : Crab_Zlib.Byte_Array;
      Source_Len : Natural) return String
   is
      use Ada.Strings.Unbounded;

      De_Nodes  : Node_Vectors.Vector;
      De_Next   : Natural := 256;
      De_Bits   : Natural := 9;
      P1        : constant Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32'(1);

      R    : Bit_Reader := (Buf_Len => Source_Len, others => <>);
      OK   : Boolean;

      Old_Code : Natural;
      New_Code : Natural;
      Char     : Interfaces.C.unsigned_char;
      Final    : Interfaces.C.unsigned_char :=
        Interfaces.C.unsigned_char'(0);

      Output   : Unbounded_String;

      procedure Emit (C : Character) is
      begin
         Append (Output, C);
      end Emit;

      function Decode_String (Code : Natural)
        return Interfaces.C.unsigned_char
      is
         --  Walk prefix chain; collect suffix bytes in reverse order,
         --  then emit forward.
         Stack : Char_Vectors.Vector;
         C     : Natural := Code;
         First : Interfaces.C.unsigned_char :=
           Interfaces.C.unsigned_char'(0);
      begin
         while C >= 256 loop
            Stack.Append (Character'Val (De_Nodes (C).Suffix));
            C := De_Nodes (C).Prefix;
         end loop;
         First := Interfaces.C.unsigned_char (C);
         Emit (Character'Val (First));
         for I in reverse 0 .. Natural (Stack.Length) - 1 loop
            Emit (Stack (I));
         end loop;
         return First;
      end Decode_String;
   begin
      --  Initialise single-byte root entries
      for I in 0 .. 255 loop
         De_Nodes.Append
           (LZW_Node'
              (Suffix => UC (I),
               Prefix => 0));
      end loop;

      Read_Code (R, De_Bits, Old_Code, OK, Source);
      if not OK then
         return "";
      end if;
      if Old_Code > 255 then
         raise LZW_Error;
      end if;

      Char := UC (Old_Code);
      Emit (Character'Val (Char));
      Final := Char;

      loop
         Read_Code (R, De_Bits, New_Code, OK, Source);
         exit when not OK;

         if New_Code < De_Next then
            Final := Decode_String (New_Code);
         else
            --  KwKwK case: new code equals the next code to be added
            Final := Decode_String (Old_Code);
            Emit (Character'Val (Final));
         end if;

         Char := Final;

         --  Add new entry to dictionary
         De_Nodes.Append
           (LZW_Node'
              (Suffix => Char,
               Prefix => Old_Code));
         De_Next := De_Next + 1;
         if De_Next >
           Natural
             (Interfaces.Shift_Left
                (P1, De_Bits))
         then
            De_Bits := De_Bits + 1;
         end if;

         Old_Code := New_Code;
      end loop;

      return To_String (Output);
   end Decompress;

end Crab_LZW;
