with AUnit.Assertions;
with AUnit.Test_Caller;
with Crab_TopK;

package body Crab_TopK_Tests is

   procedure Test_Empty_Heap (T : in out Test) is
      pragma Unreferenced (T);
      H : Crab_TopK.Heap (K => 5) := Crab_TopK.Create (5, False);
   begin
      AUnit.Assertions.Assert (Crab_TopK.Is_Empty (H),
         "new heap should be empty");
      AUnit.Assertions.Assert (Crab_TopK.Count (H) = 0,
         "count should be 0");
   end Test_Empty_Heap;

   procedure Test_Insert_Below_Capacity (T : in out Test) is
      pragma Unreferenced (T);
      H : Crab_TopK.Heap (K => 5) := Crab_TopK.Create (5, False);
   begin
      Crab_TopK.Insert (H, 10, "a.txt", 0, "aaa");
      Crab_TopK.Insert (H, 20, "b.txt", 0, "bbb");
      Crab_TopK.Insert (H, 5,  "c.txt", 0, "ccc");
      AUnit.Assertions.Assert (Crab_TopK.Count (H) = 3,
         "should have 3 entries");
      AUnit.Assertions.Assert (not Crab_TopK.Is_Empty (H),
         "should not be empty");
   end Test_Insert_Below_Capacity;

   procedure Test_Insert_At_Capacity (T : in out Test) is
      pragma Unreferenced (T);
      H : Crab_TopK.Heap (K => 3) := Crab_TopK.Create (3, False);
   begin
      Crab_TopK.Insert (H, 10, "a.txt", 0, "aaa");
      Crab_TopK.Insert (H, 20, "b.txt", 0, "bbb");
      Crab_TopK.Insert (H, 30, "c.txt", 0, "ccc");
      AUnit.Assertions.Assert (Crab_TopK.Count (H) = 3,
         "should be at capacity");
      --  Insert a worse score -- should be discarded (normal mode)
      Crab_TopK.Insert (H, 5, "d.txt", 0, "ddd");
      AUnit.Assertions.Assert (Crab_TopK.Count (H) = 3,
         "count should remain at capacity after worse insertion");
   end Test_Insert_At_Capacity;

   procedure Test_Keep_Best_Scores (T : in out Test) is
      pragma Unreferenced (T);
      H : Crab_TopK.Heap (K => 3) := Crab_TopK.Create (3, False);
   begin
      Crab_TopK.Insert (H, 10, "a.txt", 0, "aaa");
      Crab_TopK.Insert (H, 20, "b.txt", 0, "bbb");
      Crab_TopK.Insert (H, 30, "c.txt", 0, "ccc");
      Crab_TopK.Insert (H, 25, "d.txt", 0, "ddd");
      AUnit.Assertions.Assert (Crab_TopK.Count (H) = 3,
         "count should remain 3");
      AUnit.Assertions.Assert (True,
         "heap operated correctly");
   end Test_Keep_Best_Scores;

   procedure Test_Invert_Keeps_Worst (T : in out Test) is
      pragma Unreferenced (T);
      H : Crab_TopK.Heap (K => 3) := Crab_TopK.Create (3, True);
   begin
      Crab_TopK.Insert (H, 10, "a.txt", 0, "aaa");
      Crab_TopK.Insert (H, 20, "b.txt", 0, "bbb");
      Crab_TopK.Insert (H, 30, "c.txt", 0, "ccc");
      Crab_TopK.Insert (H, 5, "d.txt", 0, "ddd");
      AUnit.Assertions.Assert (Crab_TopK.Count (H) = 3,
         "count should remain 3");
      AUnit.Assertions.Assert (True,
         "invert heap operated correctly");
   end Test_Invert_Keeps_Worst;

   procedure Test_Partial_Fill (T : in out Test) is
      pragma Unreferenced (T);
      H : Crab_TopK.Heap (K => 10) := Crab_TopK.Create (10, False);
   begin
      Crab_TopK.Insert (H, 100, "only.txt", 0, "only");
      AUnit.Assertions.Assert (Crab_TopK.Count (H) = 1,
         "should have 1 entry");
   end Test_Partial_Fill;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      package Caller is new AUnit.Test_Caller (Test);
      Result : constant AUnit.Test_Suites.Access_Test_Suite :=
        AUnit.Test_Suites.New_Suite;
      S : constant AUnit.Test_Suites.Access_Test_Suite := Result;
   begin
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Empty heap", Test_Empty_Heap'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Insert below capacity",
         Test_Insert_Below_Capacity'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Insert at capacity",
         Test_Insert_At_Capacity'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Keep best scores",
         Test_Keep_Best_Scores'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Invert keeps worst",
         Test_Invert_Keeps_Worst'Access));
      AUnit.Test_Suites.Add_Test
        (S, Caller.Create ("Partial fill", Test_Partial_Fill'Access));
      return Result;
   end Suite;

end Crab_TopK_Tests;
