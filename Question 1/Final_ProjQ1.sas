libname IPEDS '~/IPEDS';
options fmtsearch=(IPEDS); 



/* ============================================================
   DSC 531 - Regression Project
   Rebuild Analytic Dataset - Team Variable Structure
   ============================================================ */

/* --- STEP 1: Response Variable --- */
proc sql;
  create table GradRates as
  select 
      Grads.UnitID,
      Cohort.Total                                    as Cohort,
      Grads.Total                                     as grads_total,
      case
         when Cohort.Total > 0 then Grads.Total / Cohort.Total
         else .
      end                                             as GradRate format=percent8.2
  from ipeds.graduation(where=(Group='Completers within 150% of normal time')) as Grads
  inner join ipeds.graduation(where=(Group='Incoming cohort (minus exclusions)')) as Cohort
      on Grads.UnitID = Cohort.UnitID
  where Cohort.Total >= 200
  ;
quit;


/* --- STEP 2: Full Merge with Team Variable Structure --- */
proc sql;
  create table Analytic as
  select
      /* Identifiers */
      g.UnitID,

      /* Response Variable */
      g.GradRate,
      g.Cohort,
      g.grads_total,

      /* ---- Characteristics (original raw codes) ---- */
      c.control,
      c.hloffer,
      c.iclevel,
      c.locale,
      c.instcat,

      /* ---- Salaries ---- */
      s.sa09mct                                       as total_staff,
      case
          when s.sa09mct > 0 then g.Cohort / s.sa09mct
          else .
      end                                             as Student_Faculty_Ratio format=12.2,

      /* ---- Individual Race/Ethnicity from graduationextended ---- */
      e.Men,
      e.Women,
      e.grwhitt                                       as White,
      e.grbkaat                                       as African_American,
      e.grasiat                                       as Asian,
      e.grhispt                                       as Hispanic,
      e.gr2mort                                       as Multi_Race,
      e.graiant + e.grnhpit                           as Race_Other,
      e.grunknt                                       as Race_Unknown,

      /* ---- Tuition and Costs (separated) ---- */
      t.tuition2                                      as In_State_Tuition,
      t.fee2                                          as Fee_InState,
      t.tuition3                                      as Out_State_Tuition,
      t.fee3                                          as Fee_OutState,
      t.roomamt                                       as Room_Cost,
      t.boardamt                                      as Board_Cost

  from GradRates as g

  /* Join characteristics */
  left join ipeds.characteristics as c
      on g.UnitID = c.UnitID

  /* Join salaries - rank 7 = all full-time instructional staff */
  left join ipeds.salaries as s
      on g.UnitID = s.UnitID
      and s.rank = 7

  /* Join graduation extended - incoming cohort rows only */
  left join ipeds.graduationextended as e
      on g.UnitID = e.UnitID
      and e.Group = 'Incoming cohort (minus exclusions)'

  /* Join tuition and costs */
  left join ipeds.tuitionandcosts as t
      on g.UnitID = t.UnitID

  /* Keep 4-year institutions only */
  where c.iclevel = 1
  ;
quit;


/* --- STEP 3: Verify --- */
proc contents data=Analytic; run;

proc means data=Analytic n nmiss mean std min max;
  var GradRate Cohort grads_total
      Student_Faculty_Ratio total_staff
      Men Women White African_American Asian Hispanic
      Multi_Race Race_Other Race_Unknown
      In_State_Tuition Fee_InState
      Out_State_Tuition Fee_OutState
      Room_Cost Board_Cost;
run;

proc freq data=Analytic;
  tables control hloffer iclevel locale instcat / missing;
run;


/* ============================================================
   DSC 531 - Part (b): Model Selection - 
   ============================================================ */

%let myvars = control hloffer iclevel locale instcat
              Student_Faculty_Ratio total_staff
              Men Women White African_American Asian 
              Hispanic Multi_Race Race_Other Race_Unknown
              In_State_Tuition Fee_InState
              Out_State_Tuition Fee_OutState
              Room_Cost Board_Cost;

%let myclass = control hloffer iclevel locale instcat;

/* --- Run 1: Forward Selection - Default SBC --- */
proc glmselect data=Analytic;
    class &myclass;
    model GradRate = &myvars / selection=forward;
    title "Run 1: Forward Selection - Default SBC";
run;

/* --- Run 2: Stepwise - SL default 0.15 --- */
proc glmselect data=Analytic;
    class &myclass;
    model GradRate = &myvars / selection=stepwise(select=SL);
    title "Run 2: Stepwise - SL (slentry=0.15 slstay=0.15)";
run;

/* --- Run 3: Stepwise - SL strict 0.05 --- */
proc glmselect data=Analytic;
    class &myclass;
    model GradRate = &myvars / selection=stepwise(select=SL)
                               slentry=0.05 slstay=0.05;
    title "Run 3: Stepwise - SL (slentry=0.05 slstay=0.05)";
run;

/* --- Run 4: Stepwise - Loose SL choose SBC --- */
proc glmselect data=Analytic;
    class &myclass;
    model GradRate = &myvars / selection=stepwise(select=SL choose=SBC)
                               slentry=0.8 slstay=0.8;
    title "Run 4: Stepwise - Loose SL entry, choose=SBC";
run;

/* --- Run 5: Stepwise - AIC --- */
proc glmselect data=Analytic;
    class &myclass;
    model GradRate = &myvars / selection=stepwise(select=AIC);
    title "Run 5: Stepwise - AIC";
run;