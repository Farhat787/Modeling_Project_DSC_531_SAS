libname IPEDS '~/IPEDS';
options fmtsearch=(IPEDS);

/* -------------------- */
/* Step 1: Prepare Data */
/* -------------------- */

/* Graduation data */
data grads_clean;
    set ipeds.Graduation;
    where group = 'Completers within 150% of normal time';

    grads_total = total;

    keep UnitID grads_total men women;
run;

/* Cohort + race proportions */
data ge_clean;
    set ipeds.graduationextended;
    where group like '%Incoming%' and total >= 200;

    Cohort = total;

    Asian = grasiat / total;
    African_American = grbkaat / total;
    Hispanic = grhispt / total;
    White = grwhitt / total;
    Multi_Race = gr2mort / total;
    Race_Other = (graiant + grnhpit) / total;
    Race_Unknown = grunknt / total;

    keep UnitID Cohort Asian African_American Hispanic White 
         Multi_Race Race_Other Race_Unknown;
run;

/* Institutional characteristics */
data char_clean;
    set ipeds.characteristics;

    keep unitid control hloffer iclevel locale instcat;
run;

/* Tuition + cost variables */
data tuition_clean;
    set ipeds.tuitionandcosts;

    In_State_Tuition = tuition2 / 1000;
    Out_State_Tuition = tuition3 / 1000;

    Fee_InState = fee2 / 1000;
    Fee_OutState = fee3 / 1000;

    Room_Cost = roomamt / 1000;
    Board_Cost = boardamt / 1000;

    keep unitid In_State_Tuition Out_State_Tuition
         Fee_InState Fee_OutState Room_Cost Board_Cost;
run;

/* Staff data */
data staff_clean;
    set ipeds.salaries;
    where put(rank, ARANK.) = 'All instructional staff total';

    unitid_char = put(unitid, 8.);
    total_staff = sa09mct;

    keep unitid_char total_staff;
run;

/* -------------------- */
/* Step 2: Merge Data   */
/* -------------------- */

proc sort data=grads_clean; by UnitID; run;
proc sort data=ge_clean; by UnitID; run;
proc sort data=char_clean; by UnitID; run;
proc sort data=tuition_clean; by UnitID; run;

data GradRates;
    merge grads_clean (in=a)
          ge_clean (in=b)
          char_clean (in=c)
          tuition_clean (in=d);
    by UnitID;

    if a and b and c and d;

    GradRate = grads_total / Cohort;
run;

/* Add staff */
data GradRates;
    set GradRates;
    unitid_char = put(unitid, 8.);
run;

proc sort data=GradRates; by unitid_char; run;
proc sort data=staff_clean; by unitid_char; run;

data GradRates;
    merge GradRates (in=a) staff_clean (in=b);
    by unitid_char;

    if a;

    Student_Faculty_Ratio = Cohort / total_staff;
run;

/* -------------------- */
/* Step 3: Median Cutoff */
/* -------------------- */

proc means data=GradRates noprint;
    var GradRate;
    output out=MedianVal median=Median_GradRate;
run;

data GradRates2;
    if _n_ = 1 then set MedianVal;
    set GradRates;

    Median_Cutoff = round(Median_GradRate, 0.001);

    if GradRate >= Median_Cutoff then AboveMedian = 1;
    else AboveMedian = 0;
run;

/* -------------------- */
/* Step 4: LASSO Model */
/* -------------------- */

proc hpgenselect data=GradRates2;
    class control hloffer iclevel locale instcat;

    model AboveMedian(event='1') =
        men women

        Asian African_American Hispanic Multi_Race Race_Other Race_Unknown

        control hloffer iclevel locale instcat

        In_State_Tuition Out_State_Tuition
        Fee_InState Fee_OutState
        Room_Cost Board_Cost

        Student_Faculty_Ratio

    / dist=binomial link=logit;

    selection method=lasso(choose=AIC);
run;

/* -------------------- */
/* Stepwise Model */
/* -------------------- */

proc hplogistic data=GradRates2;
    class control hloffer iclevel locale instcat / param=ref;

    model AboveMedian(event='1') =
        men women

        Asian African_American Hispanic Multi_Race Race_Other Race_Unknown

        control hloffer iclevel locale instcat

        In_State_Tuition Out_State_Tuition
        Fee_InState Fee_OutState
        Room_Cost Board_Cost

        Student_Faculty_Ratio

    / selection=stepwise(select=AIC stop=AIC);

run;