with Ada.Unchecked_Deallocation;

package body Crab_Buffers is

   procedure Free is
     new Ada.Unchecked_Deallocation (Element_Array, Element_Array_Access);

   --  ==================================================================

   procedure Resize (B : in out Byte_Buffer; Size : Natural) is
   begin
      if B.Data /= null then
         Free (B.Data);
      end if;
      if Size > 0 then
         B.Data := new Element_Array (1 .. Size);
      else
         B.Data := null;
      end if;
   end Resize;

   --  ==================================================================

   function Length (B : Byte_Buffer) return Natural is
   begin
      if B.Data = null then
         return 0;
      end if;
      return B.Data'Length;
   end Length;

   --  ==================================================================

   function Data_Address (B : Byte_Buffer) return System.Address is
   begin
      if B.Data = null then
         return System.Null_Address;
      end if;
      return B.Data.all'Address;
   end Data_Address;

   --  ==================================================================

   function Element
     (B : Byte_Buffer; Index : Positive) return Ada.Streams.Stream_Element
   is
   begin
      return B.Data (Index);
   end Element;

   procedure Set_Element
     (B : in out Byte_Buffer; Index : Positive;
      Value : Ada.Streams.Stream_Element)
   is
   begin
      B.Data (Index) := Value;
   end Set_Element;

   --  ==================================================================

   function Raw_Data (B : Byte_Buffer) return Element_Array_Access is
   begin
      return B.Data;
   end Raw_Data;

   --  ==================================================================

   overriding procedure Finalize (B : in out Byte_Buffer) is
   begin
      if B.Data /= null then
         Free (B.Data);
      end if;
   end Finalize;

end Crab_Buffers;
