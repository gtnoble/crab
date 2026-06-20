with Ada.Unchecked_Deallocation;

package body Crab_LZW is

   use type Interfaces.Unsigned_32;

   --  ==================================================================
   --  Bit Writer (pack codes into byte array)
   --  ==================================================================

   type Bit_Writer is record
      Buf_Off   : Natural := 0;
      Buf_Cap   : Natural;
      Bit_Buf   : Interfaces.Unsigned_32 := 0;
      Bit_Count : Natural range 0 .. 31 := 0;
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
      Val : constant Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32 (Code);
   begin
      W.Bit_Buf := W.Bit_Buf or Interfaces.Shift_Left (Val, W.Bit_Count);
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
      Bit_Buf   : Interfaces.Unsigned_32 := 0;
      Bit_Count : Natural range 0 .. 31 := 0;
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
      Mask : constant Interfaces.Unsigned_32 :=
        Interfaces.Shift_Left (Interfaces.Unsigned_32'(1), Bits) - 1;
   begin
      while R.Bit_Count < Bits loop
         Read_Bit_Byte (R, B, Rb, Source);
         if not Rb then
            OK := False;
            return;
         end if;
         R.Bit_Buf := R.Bit_Buf or
           Interfaces.Shift_Left
             (Interfaces.Unsigned_32 (B), R.Bit_Count);
         R.Bit_Count := R.Bit_Count + 8;
      end loop;
      Code := Natural (R.Bit_Buf and Mask);
      R.Bit_Buf := Interfaces.Shift_Right (R.Bit_Buf, Bits);
      R.Bit_Count := R.Bit_Count - Bits;
      OK := True;
   end Read_Code;

   --  ==================================================================
   --  Hash table operations (open addressing with generation count)
   --  ==================================================================

   subtype Hash_Index is Natural range 0 .. HASH_SIZE - 1;

   function Hash (Prefix : Natural; C : Natural) return Hash_Index is
      H : constant Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32 (Prefix) * 65599 +
        Interfaces.Unsigned_32 (C);
   begin
      return Hash_Index
        (H mod Interfaces.Unsigned_32 (HASH_SIZE));
   end Hash;

   procedure Hash_Insert
     (S      : in out LZW_Stream;
      Prefix : Natural;
      C      : Natural;
      Code   : Natural;
      OK     : out Boolean)
   is
      Idx : Hash_Index := Hash (Prefix, C);
   begin
      for I in 0 .. HASH_SIZE - 1 loop
         if S.Hash_Gen (Idx) /= S.Generation then
            S.Hash_Code (Idx) := Code;
            S.Hash_Gen (Idx)  := S.Generation;
            OK := True;
            return;
         end if;
         Idx := Hash_Index ((Natural (Idx) + 1) mod HASH_SIZE);
      end loop;
      OK := False;
   end Hash_Insert;

   function Hash_Lookup
     (S      : LZW_Stream;
      Prefix : Natural;
      C      : Natural) return Natural
   is
      Idx : Hash_Index := Hash (Prefix, C);
   begin
      for I in 0 .. HASH_SIZE - 1 loop
         if S.Hash_Gen (Idx) /= S.Generation then
            return 0;
         end if;
         declare
            Code : constant Natural := S.Hash_Code (Idx);
         begin
            if S.Prefix (Code) = Prefix
              and then Natural (S.Suffix (Code)) = C
            then
               return Code;
            end if;
         end;
         Idx := Hash_Index ((Natural (Idx) + 1) mod HASH_SIZE);
      end loop;
      return 0;
   end Hash_Lookup;

   --  ==================================================================
   --  Clear string table (reset to initial state)
   --  ==================================================================

   procedure Clear_Table (S : in out LZW_Stream) is
   begin
      S.Next_Code := FIRST_CODE;
      S.Code_Bits := INIT_BITS;
      S.Have_Prefix := False;
      for I in 0 .. 255 loop
         S.Prefix (I) := 0;
         S.Suffix (I) := UC (I);
      end loop;
      S.Generation := S.Generation + 1;
   end Clear_Table;

   --  ==================================================================
   --  Public API
   --  ==================================================================

   function Compress_Bound (Input_Size : Natural) return Natural is
   begin
      return Input_Size * 2 + 16;
   end Compress_Bound;

   --  ------------------------------------------------------------------

   function Init_Stream return LZW_Stream_Access is
      S : constant LZW_Stream_Access := new LZW_Stream;
   begin
      Clear_Table (S.all);
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
               Code := Hash_Lookup (S, Prefix, C);
               if Code /= 0 then
                  Prefix := Code;
               else
                  if S.Next_Code <= MAX_DICT then
                     S.Prefix (S.Next_Code) := Prefix;
                     S.Suffix (S.Next_Code) := UC (C);
                     declare
                        Ins_OK : Boolean;
                     begin
                        Hash_Insert (S, Prefix, C, S.Next_Code, Ins_OK);
                     end;
                     S.Next_Code := S.Next_Code + 1;
                     if S.Next_Code >
                       Natural
                         (Interfaces.Shift_Left
                            (P1, S.Code_Bits))
                     then
                        S.Code_Bits := S.Code_Bits + 1;
                     end if;
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
            Code := Hash_Lookup (S, Prefix, C);
            if Code /= 0 then
               Prefix := Code;
            else
               Write_Code (W, Prefix, S.Code_Bits, OK, Dest);
               if not OK then
                  raise LZW_Error;
               end if;

               if S.Next_Code <= MAX_DICT then
                  S.Prefix (S.Next_Code) := Prefix;
                  S.Suffix (S.Next_Code) := UC (C);
                  declare
                     Ins_OK : Boolean;
                  begin
                     Hash_Insert (S, Prefix, C, S.Next_Code, Ins_OK);
                  end;
                  S.Next_Code := S.Next_Code + 1;
                  if S.Next_Code >
                    Natural
                      (Interfaces.Shift_Left
                         (P1, S.Code_Bits))
                  then
                     S.Code_Bits := S.Code_Bits + 1;
                  end if;
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

   function Decompress
     (Source     : Crab_Zlib.Byte_Array;
      Source_Len : Natural) return String
   is
      De_Prefix : Dict_Array (0 .. MAX_DICT);
      De_Suffix : Byte_Dict_Array (0 .. MAX_DICT);
      De_Next   : Natural := FIRST_CODE;
      De_Bits   : Natural := INIT_BITS;
      P1        : constant Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32'(1);

      R    : Bit_Reader := (Buf_Len => Source_Len, others => <>);
      OK   : Boolean;

      Old_Code : Natural;
      New_Code : Natural;
      Char     : Interfaces.C.unsigned_char;
      Final    : Interfaces.C.unsigned_char :=
        Interfaces.C.unsigned_char'(0);

      --  Output buffer: generously over-allocate for testing.
      --  Worst-case a compressed byte can represent many output bytes
      --  (highly compressible input).  Source_Len * 100 is safe for
      --  the test-size inputs this subprogram handles.
      Out_Len : constant Natural := Natural'Max (1024, Source_Len * 100);
      Out_Buf : String (1 .. Out_Len);
      Out_Pos : Natural := 0;

      Stack : String (1 .. MAX_DICT + 2);
      Stack_Top : Natural;

      procedure Emit (C : Character) is
      begin
         Out_Pos := Out_Pos + 1;
         Out_Buf (Out_Pos) := C;
      end Emit;

      function Decode_String (Code : Natural)
        return Interfaces.C.unsigned_char
      is
         C     : Natural := Code;
         First : Interfaces.C.unsigned_char :=
           Interfaces.C.unsigned_char'(0);
      begin
         Stack_Top := Stack'Last;
         while C >= 256 loop
            Stack (Stack_Top) := Character'Val (De_Suffix (C));
            Stack_Top := Stack_Top - 1;
            C := De_Prefix (C);
         end loop;
         First := Interfaces.C.unsigned_char (C);
         Stack (Stack_Top) := Character'Val (First);
         Stack_Top := Stack_Top - 1;
         for I in Stack_Top + 1 .. Stack'Last loop
            Emit (Stack (I));
         end loop;
         return First;
      end Decode_String;
   begin
      --  Initialise single-byte entries
      for I in 0 .. 255 loop
         De_Prefix (I) := 0;
         De_Suffix (I) := UC (I);
      end loop;
      --  Zero-fill remaining entries so Decode_String never sees
      --  uninitialised values that would create infinite chains.
      for I in 256 .. MAX_DICT loop
         De_Prefix (I) := 0;
         De_Suffix (I) := UC (0);
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

         if New_Code = CLEAR_CODE then
            De_Next := FIRST_CODE;
            De_Bits := INIT_BITS;
            Read_Code (R, De_Bits, Old_Code, OK, Source);
            exit when not OK;
            if Old_Code > 255 then
               raise LZW_Error;
            end if;
            Char := UC (Old_Code);
            Emit (Character'Val (Char));
            Final := Char;
         elsif New_Code < De_Next then
            Final := Decode_String (New_Code);
         else
            --  KwKwK case: new code equals the next code to be added
            Final := Decode_String (Old_Code);
            Emit (Character'Val (Final));
         end if;

         Char := Final;

         if De_Next <= MAX_DICT then
            De_Prefix (De_Next) := Old_Code;
            De_Suffix (De_Next) := Char;
            De_Next := De_Next + 1;
            if De_Next >
              Natural
                (Interfaces.Shift_Left
                   (P1, De_Bits))
            then
               De_Bits := De_Bits + 1;
            end if;
         end if;

         Old_Code := New_Code;
      end loop;

      return Out_Buf (1 .. Out_Pos);
   end Decompress;

end Crab_LZW;
