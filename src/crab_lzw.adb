with Ada.Streams;
with Ada.Unchecked_Deallocation;
with Ada.Strings.Unbounded;

package body Crab_LZW is

   use type Ada.Containers.Count_Type;

   subtype Byte is Ada.Streams.Stream_Element;

   --  ==================================================================
   --  Bit Writer (pack codes into byte array)
   --  Uses Word64 accumulator so code widths beyond 31 are safe.
   --  ==================================================================

   type Bit_Writer is record
      Buf_Off   : Natural := 0;
      Buf_Cap   : Natural;
      Bit_Buf   : Word64 := 0;
      Bit_Count : Natural := 0;
   end record;

   procedure Write_Bit_Byte
     (W    : in out Bit_Writer;
      B    : Byte;
      OK   : out Boolean;
      Dest : in out Crab_Buffers.Byte_Buffer) is
   begin
      if W.Buf_Off >= W.Buf_Cap then
         OK := False;
         return;
      end if;
      Crab_Buffers.Raw_Data (Dest) (1 + W.Buf_Off) := B;
      W.Buf_Off := W.Buf_Off + 1;
      OK := True;
   end Write_Bit_Byte;

   procedure Write_Code
     (W    : in out Bit_Writer;
      Code : Natural;
      Bits : Natural;
      OK   : out Boolean;
      Dest : in out Crab_Buffers.Byte_Buffer)
   is
      Val : constant Word64 := Word64 (Code);
   begin
      W.Bit_Buf := W.Bit_Buf or
        (Val * (2 ** W.Bit_Count));
      W.Bit_Count := W.Bit_Count + Bits;
      while W.Bit_Count >= 8 loop
         Write_Bit_Byte
           (W,
            Byte (W.Bit_Buf and 16#FF#),
            OK,
            Dest);
         if not OK then
            return;
         end if;
         W.Bit_Buf := W.Bit_Buf / 256;
         W.Bit_Count := W.Bit_Count - 8;
      end loop;
      OK := True;
   end Write_Code;

   procedure Flush_Writer
     (W    : in out Bit_Writer;
      OK   : out Boolean;
      Dest : in out Crab_Buffers.Byte_Buffer) is
   begin
      if W.Bit_Count > 0 then
         Write_Bit_Byte
           (W,
            Byte (W.Bit_Buf and 16#FF#),
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
      Bit_Buf   : Word64 := 0;
      Bit_Count : Natural := 0;
   end record;

   procedure Read_Bit_Byte
     (R      : in out Bit_Reader;
      B      : out Byte;
      OK     : out Boolean;
      Source : Crab_Buffers.Byte_Buffer) is
   begin
      if R.Buf_Off >= R.Buf_Len then
         OK := False;
         return;
      end if;
      B := Crab_Buffers.Raw_Data (Source) (1 + R.Buf_Off);
      R.Buf_Off := R.Buf_Off + 1;
      OK := True;
   end Read_Bit_Byte;

   procedure Read_Code
     (R      : in out Bit_Reader;
      Bits   : Natural;
      Code   : out Natural;
      OK     : out Boolean;
      Source : Crab_Buffers.Byte_Buffer)
   is
      B  : Byte;
      Rb : Boolean;
      Mask : constant Word64 := (2 ** Bits) - 1;
   begin
      while R.Bit_Count < Bits loop
         Read_Bit_Byte (R, B, Rb, Source);
         if not Rb then
            OK := False;
            return;
         end if;
         R.Bit_Buf := R.Bit_Buf or
           (Word64 (B) * (2 ** R.Bit_Count));
         R.Bit_Count := R.Bit_Count + 8;
      end loop;
      Code := Natural (R.Bit_Buf and Mask);
      R.Bit_Buf := R.Bit_Buf / (2 ** Bits);
      R.Bit_Count := R.Bit_Count - Bits;
      OK := True;
   end Read_Code;

   --  ==================================================================
   --  Managed array wrappers — auto-free on finalization or explicit
   --  replacement.  Eliminates manual Unchecked_Deallocation.
   --  ==================================================================

   overriding procedure Finalize (A : in out Managed_Word64_Array) is
      procedure Free is
        new Ada.Unchecked_Deallocation
          (Word64_Array, Word64_Array_Access);
   begin
      if A.Data /= null then
         Free (A.Data);
      end if;
   end Finalize;

   procedure Set_Array
     (A : in out Managed_Word64_Array; Ptr : Word64_Array_Access) is
      procedure Free is
        new Ada.Unchecked_Deallocation
          (Word64_Array, Word64_Array_Access);
   begin
      if A.Data /= null then
         Free (A.Data);
      end if;
      A.Data := Ptr;
   end Set_Array;

   procedure Clear_Array (A : in out Managed_Word64_Array) is
      procedure Free is
        new Ada.Unchecked_Deallocation
          (Word64_Array, Word64_Array_Access);
   begin
      if A.Data /= null then
         Free (A.Data);
         A.Data := null;
      end if;
   end Clear_Array;

   function Ptr (A : Managed_Word64_Array) return Word64_Array_Access is
   begin
      return A.Data;
   end Ptr;

   overriding procedure Finalize (A : in out Managed_Natural_Array) is
      procedure Free is
        new Ada.Unchecked_Deallocation
          (Natural_Array, Natural_Array_Access);
   begin
      if A.Data /= null then
         Free (A.Data);
      end if;
   end Finalize;

   procedure Set_Array
     (A : in out Managed_Natural_Array; Ptr : Natural_Array_Access) is
      procedure Free is
        new Ada.Unchecked_Deallocation
          (Natural_Array, Natural_Array_Access);
   begin
      if A.Data /= null then
         Free (A.Data);
      end if;
      A.Data := Ptr;
   end Set_Array;

   procedure Clear_Array (A : in out Managed_Natural_Array) is
      procedure Free is
        new Ada.Unchecked_Deallocation
          (Natural_Array, Natural_Array_Access);
   begin
      if A.Data /= null then
         Free (A.Data);
         A.Data := null;
      end if;
   end Clear_Array;

   function Ptr (A : Managed_Natural_Array) return Natural_Array_Access is
   begin
      return A.Data;
   end Ptr;

   --  ==================================================================
   --  Custom open-addressing hash table
   --  ==================================================================
   --  Uses linear probing with power-of-2 sizing and 50% max load factor.
   --
   --  Key packing: Word64(Prefix) * 257 + Word64(Suffix) + 1
   --  The +1 ensures 0 means "empty slot" (since (0,0) is a valid key).
   --  Multiplication by 257 (= 256+1) mixes Prefix bits into the low byte
   --  where Suffix lives, giving good distribution for the low-bit mask.

   function Pack_Key (Prefix, Suffix : Natural) return Word64 is
     (Word64 (Prefix) * 257 + Word64 (Suffix) + 1);

   procedure Hash_Grow (S : in out LZW_Stream; Min_Cap : Natural) is
      --  Compute new capacity: next power of 2 >= Min_Cap
      New_Cap   : Natural := 8;
      New_Mask  : Natural := 7;
      New_Keys  : Word64_Array_Access;
      New_Vals  : Natural_Array_Access;
      Old_Keys  : Word64_Array_Access := Ptr (S.Hash_Keys);
      Old_Vals  : Natural_Array_Access := Ptr (S.Hash_Vals);
      Old_Mask  : constant Natural := S.Hash_Mask;
   begin
      --  Find next power of 2 >= Min_Cap
      while New_Cap < Min_Cap loop
         New_Cap := New_Cap * 2;
      end loop;
      New_Mask := New_Cap - 1;

      New_Keys := new Word64_Array (0 .. New_Mask);
      New_Vals := new Natural_Array (0 .. New_Mask);

      --  Explicitly zero the arrays (GNAT may not default-initialize)
      for I in 0 .. New_Mask loop
         New_Keys (I) := 0;
         New_Vals (I) := 0;
      end loop;

      --  Rehash existing entries
      if Old_Keys /= null then
         for I in 0 .. Old_Mask loop
            declare
               K : constant Word64 := Old_Keys (I);
            begin
               if K /= 0 then
                  declare
                     Idx : Natural :=
                       Natural (K and Word64 (New_Mask));
                  begin
                     while New_Keys (Idx) /= 0 loop
                        Idx := (Idx + 1) mod (New_Mask + 1);
                     end loop;
                     New_Keys (Idx) := K;
                     New_Vals (Idx) := Old_Vals (I);
                  end;
               end if;
            end;
         end loop;
      end if;

      --  Replace managed arrays (Set_Array frees old storage)
      Set_Array (S.Hash_Keys, New_Keys);
      Set_Array (S.Hash_Vals, New_Vals);
      S.Hash_Mask := New_Mask;
   end Hash_Grow;

   procedure Hash_Reserve (S : in out LZW_Stream; Additional : Natural) is
      Needed : constant Natural := S.Hash_Count + Additional;
      Cap    : constant Natural :=
        (if Ptr (S.Hash_Keys) = null then 0 else S.Hash_Mask + 1);
   begin
      --  Maintain at most 50% load factor
      if Needed > Cap / 2 then
         Hash_Grow (S, Needed * 2);
      end if;
   end Hash_Reserve;

   function Hash_Find
     (S : LZW_Stream; Prefix, Suffix : Natural) return Natural
   is
      K   : constant Word64 := Pack_Key (Prefix, Suffix);
      Idx : Natural;
      Keys : constant Word64_Array_Access := Ptr (S.Hash_Keys);
      Vals : constant Natural_Array_Access := Ptr (S.Hash_Vals);
   begin
      if Keys = null then
         return 0;
      end if;
      Idx := Natural (K and Word64 (S.Hash_Mask));
      declare
         Probe_Count : Natural := 0;
      begin
         loop
            declare
               Stored : constant Word64 := Keys (Idx);
            begin
               if Stored = 0 then
                  return 0;
               elsif Stored = K then
                  return Vals (Idx);
               end if;
            end;
            Idx := (Idx + 1) mod (S.Hash_Mask + 1);
            Probe_Count := Probe_Count + 1;
            if Probe_Count > S.Hash_Mask + 1 then
               raise LZW_Error with "hash table full";
            end if;
         end loop;
      end;
   end Hash_Find;

   procedure Hash_Insert
     (S : in out LZW_Stream; Prefix, Suffix, Code : Natural)
   is
      K   : constant Word64 := Pack_Key (Prefix, Suffix);
      Idx : Natural;
      Keys : Word64_Array_Access := Ptr (S.Hash_Keys);
      Vals : Natural_Array_Access := Ptr (S.Hash_Vals);
   begin
      --  Ensure room (50% load factor)
      if Keys = null
        or else S.Hash_Count >= (S.Hash_Mask + 1) / 2
      then
         declare
            New_Cap : constant Natural :=
              (if Keys = null then 16
               else (S.Hash_Mask + 1) * 2);
         begin
            Hash_Grow (S, New_Cap);
         end;
         Keys := Ptr (S.Hash_Keys);
         Vals := Ptr (S.Hash_Vals);
      end if;

      Idx := Natural (K and Word64 (S.Hash_Mask));
      declare
         Ins_Probe : Natural := 0;
      begin
         while Keys (Idx) /= 0 loop
            Idx := (Idx + 1) mod (S.Hash_Mask + 1);
            Ins_Probe := Ins_Probe + 1;
            if Ins_Probe > S.Hash_Mask + 1 then
               raise LZW_Error with "hash insert table full";
            end if;
         end loop;
      end;
      Keys (Idx) := K;
      Vals (Idx) := Code;
      S.Hash_Count := S.Hash_Count + 1;
   end Hash_Insert;

   procedure Hash_Clear (S : in out LZW_Stream) is
   begin
      Clear_Array (S.Hash_Keys);
      Clear_Array (S.Hash_Vals);
      S.Hash_Mask  := 0;
      S.Hash_Count := 0;
   end Hash_Clear;

   --  ==================================================================
   --  LZW operations using the custom hash table
   --  ==================================================================

   function Lookup
     (S : LZW_Stream; Prefix : Natural; C : Natural) return Natural is
   begin
      return Hash_Find (S, Prefix, C);
   end Lookup;

   procedure Insert
     (S : in out LZW_Stream; Prefix : Natural; C : Natural)
   is
      New_Code : constant Natural := S.Next_Code;
      New_Node : constant LZW_Node :=
        (Suffix => Character'Val (C),
         Prefix => Prefix);
   begin
      S.Nodes.Append (New_Node);
      Hash_Insert (S, Prefix, C, New_Code);
      S.Next_Code := New_Code + 1;
   end Insert;

   --  ==================================================================
   --  Initialise root nodes (single-byte codes 0..255)
   --  ==================================================================

   procedure Init_Roots (S : in out LZW_Stream) is
   begin
      S.Nodes.Clear;
      Hash_Clear (S);
      S.Nodes.Reserve_Capacity (256);
      for I in 0 .. 255 loop
         S.Nodes.Append
           (LZW_Node'
              (Suffix => Character'Val (I),
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

   procedure Load_Dict (S : in out LZW_Stream; Dict : String) is
      Prefix : Natural := 0;
      Code   : Natural;
      First  : Boolean := True;
   begin
      S.Nodes.Reserve_Capacity
        (S.Nodes.Length + Ada.Containers.Count_Type (Dict'Length));
      Hash_Reserve (S, Dict'Length);
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
                  if S.Next_Code > 2 ** S.Code_Bits then
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
      Dest     : in out Crab_Buffers.Byte_Buffer;
      Level    : Integer;
      Dest_Len : out Natural)
   is
      pragma Unreferenced (Level);

      W      : Bit_Writer :=
        (Buf_Cap => Crab_Buffers.Length (Dest), others => <>);
      OK     : Boolean;

      Prefix : Natural := 0;
      Code   : Natural;
      C      : Natural;
   begin
      if S.Have_Prefix then
         Prefix := S.Resid_Prefix;
         S.Have_Prefix := False;
      end if;

      S.Nodes.Reserve_Capacity
        (S.Nodes.Length + Ada.Containers.Count_Type (Source'Length));
      Hash_Reserve (S, Source'Length);
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
               if S.Next_Code > 2 ** S.Code_Bits then
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

   procedure Reset_Stream (S : in out LZW_Stream) is
   begin
      Init_Roots (S);
   end Reset_Stream;

   --  ------------------------------------------------------------------

   function Compress_Bare
     (Source : String;
      Dict   : String) return Natural
   is
      S    : LZW_Stream;
      Buf  : Crab_Buffers.Byte_Buffer;
      Dlen : Natural;
   begin
      Init_Roots (S);
      Crab_Buffers.Resize (Buf, Compress_Bound (Source'Length));
      Load_Dict (S, Dict);
      Compress_Stream (S, Source, Buf, 0, Dlen);
      return Dlen;
   end Compress_Bare;

   --  ==================================================================
   --  Decompression (for roundtrip testing)
   --  ==================================================================

   package Char_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Character);

   function Decompress
     (Source     : Crab_Buffers.Byte_Buffer;
      Source_Len : Natural) return String
   is
      use Ada.Strings.Unbounded;

      De_Nodes  : Node_Vectors.Vector;
      De_Next   : Natural := 256;
      De_Bits   : Natural := 9;

      R    : Bit_Reader := (Buf_Len => Source_Len, others => <>);
      OK   : Boolean;

      Old_Code : Natural;
      New_Code : Natural;
      Char     : Character;
      Final    : Character := Character'Val (0);

      Output   : Unbounded_String;

      procedure Emit (C : Character) is
      begin
         Append (Output, C);
      end Emit;

      function Decode_String (Code : Natural)
        return Character
      is
         --  Walk prefix chain; collect suffix bytes in reverse order,
         --  then emit forward.
         Stack : Char_Vectors.Vector;
         C     : Natural := Code;
         First : Character := Character'Val (0);
      begin
         while C >= 256 loop
            Stack.Append (De_Nodes (C).Suffix);
            C := De_Nodes (C).Prefix;
         end loop;
         First := Character'Val (C);
         Emit (First);
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
              (Suffix => Character'Val (I),
               Prefix => 0));
      end loop;

      Read_Code (R, De_Bits, Old_Code, OK, Source);
      if not OK then
         return "";
      end if;
      if Old_Code > 255 then
         raise LZW_Error;
      end if;

      Char := Character'Val (Old_Code);
      Emit (Char);
      Final := Char;

      loop
         Read_Code (R, De_Bits, New_Code, OK, Source);
         exit when not OK;

         if New_Code < De_Next then
            Final := Decode_String (New_Code);
         else
            --  KwKwK case: new code equals the next code to be added
            Final := Decode_String (Old_Code);
            Emit (Final);
         end if;

         Char := Final;

         --  Add new entry to dictionary
         De_Nodes.Append
           (LZW_Node'
              (Suffix => Char,
               Prefix => Old_Code));
         De_Next := De_Next + 1;
         if De_Next > 2 ** De_Bits then
            De_Bits := De_Bits + 1;
         end if;

         Old_Code := New_Code;
      end loop;

      return To_String (Output);
   end Decompress;

end Crab_LZW;
