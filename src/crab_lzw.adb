with Ada.Streams;
with Ada.Unchecked_Deallocation;
with Ada.Strings.Unbounded;
with Ada.Containers.Vectors;

package body Crab_LZW is

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
   --  Node array management (raw heap array, no controlled-type overhead)
   --  ==================================================================

   procedure Free_Nodes is
     new Ada.Unchecked_Deallocation
       (LZW_Node_Array, LZW_Node_Array_Access);

   overriding procedure Finalize (S : in out LZW_Stream) is
   begin
      if S.Nodes /= null then
         Free_Nodes (S.Nodes);
      end if;
   end Finalize;

   procedure Node_Reserve (S : in out LZW_Stream; N : Natural) is
   begin
      if N > S.Node_Cap then
         declare
            New_Cap : Natural := (if S.Node_Cap = 0 then 256
                                   else S.Node_Cap);
            New_Arr : LZW_Node_Array_Access;
         begin
            while New_Cap < N loop
               New_Cap := New_Cap * 2;
            end loop;
            New_Arr := new LZW_Node_Array (0 .. New_Cap - 1);
            if S.Nodes /= null then
               New_Arr (0 .. S.Next_Code - 1) :=
                 S.Nodes (0 .. S.Next_Code - 1);
               Free_Nodes (S.Nodes);
            end if;
            S.Nodes := New_Arr;
            S.Node_Cap := New_Cap;
         end;
      end if;
   end Node_Reserve;

   procedure Node_Append (S : in out LZW_Stream; N : LZW_Node) is
   begin
      if S.Next_Code >= S.Node_Cap then
         Node_Reserve (S, S.Next_Code + 1);
      end if;
      S.Nodes (S.Next_Code) := N;
      S.Next_Code := S.Next_Code + 1;
   end Node_Append;

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

   Tombstone : constant Word64 := Word64'Last;
   --  Tombstone marker for deleted hash-table entries.
   --  Must be a value that Pack_Key can never produce.
   --  Pack_Key min is +1, so Word64'Last is safe.

   procedure Hash_Grow (S : in out LZW_Stream; Min_Cap : Natural) is
      pragma Suppress (Index_Check);
      pragma Suppress (Overflow_Check);
      pragma Suppress (Range_Check);
      --  Compute new capacity: next power of 2 >= Min_Cap
      New_Cap   : Natural := 8;
      New_Mask  : Natural := 7;
      New_Keys  : Word64_Array_Access;
      New_Vals  : Natural_Array_Access;
      Old_Keys  : constant Word64_Array_Access := Ptr (S.Hash_Keys);
      Old_Vals  : constant Natural_Array_Access := Ptr (S.Hash_Vals);
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
               if K /= 0 and then K /= Tombstone then
                  declare
                     Idx : Natural :=
                       Natural (K and Word64 (New_Mask));
                  begin
                     while New_Keys (Idx) /= 0 loop
                        Idx := Natural
                          (Word64 (Idx + 1) and Word64 (New_Mask));
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
      S.Hash_Deleted_Count := 0;  -- tombstones not copied
   end Hash_Grow;

   procedure Hash_Reserve (S : in out LZW_Stream; Additional : Natural) is
      Cap    : constant Natural :=
        (if Ptr (S.Hash_Keys) = null then 0 else S.Hash_Mask + 1);
   begin
      --  Maintain at most 50% load factor.
      --  Count only live entries (not tombstones) to avoid
      --  runaway growth from delete-heavy workloads.
      if S.Hash_Count + Additional > Cap / 2 then
         Hash_Grow (S, (S.Hash_Count + Additional) * 2);
      end if;
   end Hash_Reserve;

   function Hash_Find
     (S : LZW_Stream; Prefix, Suffix : Natural) return Natural
   is
      pragma Suppress (Index_Check);
      pragma Suppress (Overflow_Check);
      pragma Suppress (Range_Check);
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
               elsif Stored = Tombstone then
                  null;  -- keep probing past deleted slots
               elsif Stored = K then
                  return Vals (Idx);
               end if;
            end;
            Idx := Natural (Word64 (Idx + 1) and Word64 (S.Hash_Mask));
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
      Probe : Natural;
      First_Tomb : Integer := -1;
   begin
      --  Ensure room (50% load factor on occupied slots)
      if Keys = null
        or else S.Hash_Count + S.Hash_Deleted_Count >= (S.Hash_Mask + 1) / 2
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
         First_Tomb := -1;  -- rehashed away all tombstones
      end if;

      Idx := Natural (K and Word64 (S.Hash_Mask));
      Probe := 0;
      while Keys (Idx) /= 0 loop
         if Keys (Idx) = K then
            --  Key already present — update value (should not happen in
            --  normal LZW use, but provides safety for the hash table)
            Vals (Idx) := Code;
            return;
         end if;
         if Keys (Idx) = Tombstone and then First_Tomb < 0 then
            First_Tomb := Idx;
         end if;
         Idx := Natural (Word64 (Idx + 1) and Word64 (S.Hash_Mask));
         Probe := Probe + 1;
         if Probe > S.Hash_Mask + 1 then
            raise LZW_Error with "hash insert table full";
         end if;
      end loop;

      if First_Tomb >= 0 then
         --  Reuse a tombstone slot — reclaim a "deleted" slot
         Idx := First_Tomb;
         S.Hash_Deleted_Count := S.Hash_Deleted_Count - 1;
      end if;

      Keys (Idx) := K;
      Vals (Idx) := Code;
      S.Hash_Count := S.Hash_Count + 1;
   end Hash_Insert;

   procedure Hash_Delete
     (S : in out LZW_Stream; Prefix, Suffix : Natural)
   is
      pragma Suppress (Index_Check);
      pragma Suppress (Overflow_Check);
      pragma Suppress (Range_Check);
      K    : constant Word64 := Pack_Key (Prefix, Suffix);
      Idx  : Natural;
      Keys : constant Word64_Array_Access := Ptr (S.Hash_Keys);
      Mask : constant Natural := S.Hash_Mask;
   begin
      if Keys = null then
         raise LZW_Error with "hash delete: empty table";
      end if;

      --  Find the entry
      Idx := Natural (K and Word64 (Mask));
      declare
         Probe_Count : Natural := 0;
      begin
         while Keys (Idx) /= 0 loop
            if Keys (Idx) = K then
               --  Found it — place a tombstone instead of rehashing
               Keys (Idx) := Tombstone;
               S.Hash_Count := S.Hash_Count - 1;
               S.Hash_Deleted_Count := S.Hash_Deleted_Count + 1;
               return;
            end if;
            Idx := Natural (Word64 (Idx + 1) and Word64 (Mask));
            Probe_Count := Probe_Count + 1;
            if Probe_Count > Mask + 1 then
               raise LZW_Error with "hash delete: key not found";
            end if;
         end loop;
      end;
      raise LZW_Error with "hash delete: key not found";
   end Hash_Delete;

   procedure Hash_Clear (S : in out LZW_Stream) is
   begin
      Clear_Array (S.Hash_Keys);
      Clear_Array (S.Hash_Vals);
      S.Hash_Mask  := 0;
      S.Hash_Count := 0;
      S.Hash_Deleted_Count := 0;
   end Hash_Clear;

   --  ==================================================================
   --  LZW operations using the custom hash table
   --  ==================================================================

   --  Single-pass hash find-or-insert for the hot compression loop.
   --  Walks the table once per byte instead of twice (find + insert).
   --  On hit:  sets Prefix to the found code, Found := True.
   --  On miss: evicts, allocates a new code, inserts at the empty/
   --           tombstone slot discovered during the walk, updates
   --           Ref_Count / Active_Codes, sets Prefix := C,
   --           Found := False.
   procedure Evict_One (S : in out LZW_Stream);
   procedure Lookup_Or_Insert
     (S      : in out LZW_Stream;
      Prefix : in out Natural;
      C      : Natural;
      Found  : out Boolean)
   is
      pragma Suppress (Index_Check);
      pragma Suppress (Overflow_Check);
      pragma Suppress (Range_Check);
      K          : constant Word64 := Pack_Key (Prefix, C);
      Keys       : Word64_Array_Access;
      Vals       : Natural_Array_Access;
      Mask       : Natural;
      Idx        : Natural;
      Probe      : Natural;
      First_Tomb : Integer := -1;
      New_Code   : Natural;
   begin
      --  Ensure capacity (50 % load factor on occupied + deleted slots)
      Keys := Ptr (S.Hash_Keys);
      Vals := Ptr (S.Hash_Vals);
      if Keys = null
        or else S.Hash_Count + S.Hash_Deleted_Count
                >= (S.Hash_Mask + 1) / 2
      then
         declare
            New_Cap : constant Natural :=
              (if Keys = null then 16
               else (S.Hash_Mask + 1) * 2);
         begin
            Hash_Grow (S, New_Cap);
         end;
         Keys       := Ptr (S.Hash_Keys);
         Vals       := Ptr (S.Hash_Vals);
         First_Tomb := -1;
      end if;

      Mask  := S.Hash_Mask;
      Idx   := Natural (K and Word64 (Mask));
      Probe := 0;

      loop
         declare
            Stored : constant Word64 := Keys (Idx);
         begin
            if Stored = 0 then
               Found := False;
               if First_Tomb >= 0 then
                  Idx := First_Tomb;
                  S.Hash_Deleted_Count := S.Hash_Deleted_Count - 1;
               end if;
               goto Do_Insert;
            elsif Stored = Tombstone then
               if First_Tomb < 0 then
                  First_Tomb := Idx;
               end if;
            elsif Stored = K then
               Found  := True;
               Prefix := Vals (Idx);
               return;
            end if;
         end;

         Idx := Natural (Word64 (Idx + 1) and Word64 (Mask));
         Probe := Probe + 1;
         if Probe > Mask + 1 then
            raise LZW_Error with "hash table full";
         end if;
      end loop;

      <<Do_Insert>>
      --  Evict if at capacity (bounded mode)
      if S.Max_Codes > 0 and then S.Active_Codes >= S.Max_Codes then
         Evict_One (S);
      end if;

      --  Allocate code from free list or Next_Code
      if S.Free_Head /= 0 then
         New_Code := S.Free_Head;
         S.Free_Head := S.Nodes (New_Code).Prefix;  -- pop
         S.Nodes (New_Code) :=
           LZW_Node'(Suffix     => Character'Val (C),
                      Prefix     => Prefix,
                      Ref_Count  => 0,
                      Free       => False);
      else
         New_Code := S.Next_Code;
         Node_Append
           (S,
            LZW_Node'(Suffix     => Character'Val (C),
                       Prefix     => Prefix,
                       Ref_Count  => 0,
                       Free       => False));
      end if;

      --  Insert at the empty/tombstone slot found during the walk
      Keys (Idx)     := K;
      Vals (Idx)     := New_Code;
      S.Hash_Count   := S.Hash_Count + 1;

      --  Update the prefix node and active-count
      S.Nodes (Prefix).Ref_Count := S.Nodes (Prefix).Ref_Count + 1;
      S.Active_Codes := S.Active_Codes + 1;

      --  On miss the new prefix is the single-byte root
      Prefix := C;
   end Lookup_Or_Insert;

   --  ==================================================================
   --  Eviction (bounded mode) — random leaf eviction
   --  ==================================================================

   --  LCG multiplier (musl/newlib rand64).  State = State * Mul + 1.
   --  Both compressor and decompressor share the same seed and advance
   --  identically, keeping eviction deterministic.
   Rand_Mul : constant Word64 := 16#5851_F42D_4C95_7F2D#;

   procedure Evict_One (S : in out LZW_Stream) is
      pragma Suppress (Index_Check);
      pragma Suppress (Overflow_Check);
      pragma Suppress (Range_Check);
      Span : constant Natural := S.Next_Code - 256;
   begin
      --  Random leaf eviction: probe random codes until we find
      --  a non-free leaf (Ref_Count = 0).  No second chance —
      --  any leaf is equally likely to be evicted.
      --  With typical leaf density ~50%, average 2 probes per eviction.
      loop
         S.Rand_State := S.Rand_State * Rand_Mul + 1;
         --  Use high 32 bits of LCG state for the candidate index.
         --  Shift-right avoids the slow 64-bit DIV instruction.
         declare
            Candidate : constant Natural :=
              256 + Natural
                ((S.Rand_State / 2**32) mod Word64 (Span));
         begin
            if not S.Nodes (Candidate).Free
              and then S.Nodes (Candidate).Ref_Count = 0
            then
               --  Evict this leaf
               declare
                  Victim : constant Natural := Candidate;
                  Parent : constant Natural :=
                    S.Nodes (Victim).Prefix;
               begin
                  Hash_Delete
                    (S, Parent,
                     Character'Pos (S.Nodes (Victim).Suffix));
                  if Parent >= 256 then
                     S.Nodes (Parent).Ref_Count :=
                       S.Nodes (Parent).Ref_Count - 1;
                  end if;

                  --  Mark as free and chain into free list
                  S.Nodes (Victim).Free := True;
                  S.Nodes (Victim).Prefix := S.Free_Head;
                  S.Free_Head := Victim;
                  S.Active_Codes := S.Active_Codes - 1;
                  return;
               end;
            end if;
         end;
      end loop;
   end Evict_One;

   --  ==================================================================

   --  ==================================================================
   --  Initialise root nodes (single-byte codes 0..255)
   --  ==================================================================

   procedure Init_Roots (S : in out LZW_Stream) is
      Saved_Max_Codes : constant Natural := S.Max_Codes;
   begin
      --  Free old node array, if any
      if S.Nodes /= null then
         Free_Nodes (S.Nodes);
         S.Nodes := null;
      end if;
      S.Node_Cap := 0;
      S.Next_Code := 0;

      Hash_Clear (S);

      --  Pre-size the hash table when bounded, to forestall
      --  repeated growth from the staircase 16→32→…→stable.
      --  We need room for Max_Codes live entries plus up to 2×
      --  tombstones from churn.  Round up to the next power of 2.
      if Saved_Max_Codes > 0 then
         declare
            Desired : constant Natural := Saved_Max_Codes * 4;
         begin
            Hash_Reserve (S, Desired);
         end;
      end if;

      --  Pre-allocate 256 root entries (node array)
      Node_Reserve (S, 256);
      for I in 0 .. 255 loop
         Node_Append
           (S,
            LZW_Node'
              (Suffix     => Character'Val (I),
               Prefix     => 0,
               Ref_Count  => 0,
               Free       => False));
      end loop;

      S.Next_Code    := 256;
      S.Code_Bits    := 9;
      S.Have_Prefix  := False;
      S.Max_Codes    := Saved_Max_Codes;
      S.Active_Codes := 0;
      S.Rand_State   := 1;
      S.Free_Head    := 0;
   end Init_Roots;

   --  ==================================================================
   --  Public API
   --  ==================================================================

   procedure Set_Max_Codes (S : in out LZW_Stream; N : Natural) is
   begin
      S.Max_Codes := N;
   end Set_Max_Codes;

   --  ------------------------------------------------------------------

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
      Found  : Boolean;
      First  : Boolean := True;
   begin
      --  In unbounded mode, pre-allocate capacity
      if S.Max_Codes = 0 then
         Node_Reserve (S, S.Next_Code + Dict'Length);
         Hash_Reserve (S, Dict'Length);
      end if;

      for I in Dict'Range loop
         declare
            C : constant Natural := Character'Pos (Dict (I));
         begin
            if First then
               Prefix := C;
               First := False;
            else
               Lookup_Or_Insert (S, Prefix, C, Found);
               if not Found then
                  if S.Next_Code > 2 ** S.Code_Bits then
                     S.Code_Bits := S.Code_Bits + 1;
                  end if;
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
      C      : Natural;
   begin
      if S.Have_Prefix then
         Prefix := S.Resid_Prefix;
         S.Have_Prefix := False;
      end if;

      --  In unbounded mode, pre-allocate capacity
      if S.Max_Codes = 0 then
         Node_Reserve (S, S.Next_Code + Source'Length);
         Hash_Reserve (S, Source'Length);
      end if;

      for I in Source'Range loop
         C := Character'Pos (Source (I));

         if Prefix = 0 then
            Prefix := C;
         else
            declare
               Old_Prefix : constant Natural := Prefix;
               Found      : Boolean;
            begin
               Lookup_Or_Insert (S, Prefix, C, Found);
               if not Found then
                  Write_Code (W, Old_Prefix, S.Code_Bits, OK, Dest);
                  if not OK then
                     raise LZW_Error;
                  end if;

                  if S.Next_Code > 2 ** S.Code_Bits then
                     S.Code_Bits := S.Code_Bits + 1;
                  end if;
               end if;
            end;
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
   --  Mirrors the compressor's random eviction deterministically
   --  so that bounded-mode streams decode correctly.
   --  ==================================================================

   package Char_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Character);

   function Decompress
     (Source     : Crab_Buffers.Byte_Buffer;
      Source_Len : Natural;
      Max_Codes  : Natural := 0) return String
   is
      use Ada.Strings.Unbounded;

      --  Raw node array for the decompressor dictionary
      De_Nodes      : LZW_Node_Array_Access := null;
      De_Node_Cap   : Natural := 0;
      De_Next       : Natural := 0;
      De_Bits       : Natural := 9;
      De_Max_Codes  : constant Natural := Max_Codes;
      De_Active     : Natural := 0;
      De_Rand_State : Word64 := 1;
      De_Free_Head  : Natural := 0;

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

      --  Local helpers for raw node array management.
      --  Must mirror the compressor's Node_Append / init logic.

      procedure De_Node_Reserve (N : Natural) is
         procedure Free is
           new Ada.Unchecked_Deallocation
             (LZW_Node_Array, LZW_Node_Array_Access);
      begin
         if N > De_Node_Cap then
            declare
               New_Cap : Natural :=
                 (if De_Node_Cap = 0 then 256 else De_Node_Cap);
               New_Arr : LZW_Node_Array_Access;
            begin
               while New_Cap < N loop
                  New_Cap := New_Cap * 2;
               end loop;
               New_Arr := new LZW_Node_Array (0 .. New_Cap - 1);
               if De_Nodes /= null then
                  New_Arr (0 .. De_Next - 1) :=
                    De_Nodes (0 .. De_Next - 1);
                  Free (De_Nodes);
               end if;
               De_Nodes := New_Arr;
               De_Node_Cap := New_Cap;
            end;
         end if;
      end De_Node_Reserve;

      procedure De_Node_Append (N : LZW_Node; Code : out Natural) is
      begin
         if De_Next >= De_Node_Cap then
            De_Node_Reserve (De_Next + 1);
         end if;
         Code := De_Next;
         De_Nodes (De_Next) := N;
         De_Next := De_Next + 1;
      end De_Node_Append;

      --  Mirror of the compressor's Evict_One for deterministic sync.
      procedure De_Evict_One is
         Span : constant Natural := De_Next - 256;
      begin
         loop
            De_Rand_State := De_Rand_State * Rand_Mul + 1;
            declare
               Candidate : constant Natural :=
                 256 + Natural
                   ((De_Rand_State / 2**32) mod Word64 (Span));
            begin
               if not De_Nodes (Candidate).Free
                 and then De_Nodes (Candidate).Ref_Count = 0
               then
                  --  Evict this leaf
                  declare
                     Victim : constant Natural := Candidate;
                     Parent : constant Natural :=
                       De_Nodes (Victim).Prefix;
                  begin
                     if Parent >= 256 then
                        De_Nodes (Parent).Ref_Count :=
                          De_Nodes (Parent).Ref_Count - 1;
                     end if;
                     De_Nodes (Victim).Free := True;
                     De_Nodes (Victim).Prefix := De_Free_Head;
                     De_Free_Head := Victim;
                     De_Active := De_Active - 1;
                     return;
                  end;
               end if;
            end;
         end loop;
      end De_Evict_One;

      procedure De_Insert (Prefix_Code : Natural; Suffix_Char : Character) is
         New_Code : Natural;
         New_Node : constant LZW_Node :=
           (Suffix     => Suffix_Char,
            Prefix     => Prefix_Code,
            Ref_Count  => 0,
            Free       => False);
      begin
         --  Evict if at capacity (bounded-mode decompression)
         if De_Max_Codes > 0 and then De_Active >= De_Max_Codes then
            De_Evict_One;
         end if;

         --  Allocate from free list or append
         if De_Free_Head /= 0 then
            New_Code := De_Free_Head;
            De_Free_Head := De_Nodes (New_Code).Prefix;
            De_Nodes (New_Code) := New_Node;
         else
            De_Node_Append (New_Node, New_Code);
         end if;

         De_Nodes (Prefix_Code).Ref_Count :=
           De_Nodes (Prefix_Code).Ref_Count + 1;
         De_Active := De_Active + 1;
      end De_Insert;

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

      procedure De_Free_Nodes is
        new Ada.Unchecked_Deallocation
          (LZW_Node_Array, LZW_Node_Array_Access);
   begin
      --  Initialise single-byte root entries
      De_Node_Reserve (256);
      for I in 0 .. 255 loop
         De_Nodes (I) :=
           LZW_Node'
            (Suffix     => Character'Val (I),
             Prefix     => 0,
             Ref_Count  => 0,
             Free       => False);
      end loop;
      De_Next := 256;

      Read_Code (R, De_Bits, Old_Code, OK, Source);
      if not OK then
         if De_Nodes /= null then
            De_Free_Nodes (De_Nodes);
         end if;
         return "";
      end if;
      if Old_Code > 255 then
         if De_Nodes /= null then
            De_Free_Nodes (De_Nodes);
         end if;
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

         --  Add new entry to dictionary (mirrors compressor's Insert)
         De_Insert (Old_Code, Char);
         if De_Next > 2 ** De_Bits then
            De_Bits := De_Bits + 1;
         end if;

         Old_Code := New_Code;
      end loop;

      if De_Nodes /= null then
         De_Free_Nodes (De_Nodes);
      end if;
      return To_String (Output);
   end Decompress;

end Crab_LZW;
