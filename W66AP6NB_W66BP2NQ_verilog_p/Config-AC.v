//timeunit in ps
parameter int KI              = 1000;
parameter int MI              = KI*KI;
parameter int GI              = KI*KI*KI;

//memory bank/row/col/io
   `define   ca_wid            6 
   `define   io_wid           16   
   `define   bank_wid          3 
   `define   row_max_wid      16 
   `define   row_wid          13                 //1Gb       
   `define   col_wid          10 
 
   `define   row_size         ( 1 << `row_wid )
   `define   row_max_size     ( 1 << `row_max_wid )
   `define   bank_size        ( 1 << `bank_wid )

   `define   dqs_wid         `io_wid/8
   `define   dmi_wid         `io_wid/8

   `define   mem_size         (1<<`bank_wid+ `row_wid +` col_wid)  

parameter int ADDR_BITS       = `bank_wid+ `row_wid +`col_wid; 
parameter int STOP_ON_ERROR   = 0;  // Set to 1, stop simulation on errors
parameter int CL_MAX          = 40;
parameter int BL_max          = 32;
parameter int MAX_PIPE        = 2*CL_MAX + 2*BL_max;
parameter int MR_ID_MAX       = 51;
    
  
// speed grade
typedef enum { SG1600, SG2400, SG2667, SG3200, SG3733, SG4267, NUM_SG } DDRSG_T;
`ifdef  T4267
    parameter int ddr_sg    = SG4267; 
`elsif  T3733
    parameter int ddr_sg    = SG3733; 
`elsif  T3200
    parameter int ddr_sg    = SG3200; 
`elsif  T2667
    parameter int ddr_sg    = SG2667;
`elsif  T2400
    parameter int ddr_sg    = SG2400;
`elsif  T1600
    parameter int ddr_sg    = SG1600;
`else
    parameter int ddr_sg    = SG1600;
`endif
  
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Timing parameters 
// Speed Grade                        SG1600,     SG2400,     SG2667,     SG3200,       SG3733,       SG4267
parameter int tWLS       [NUM_SG] = '{150,        100,        92,         75,           63,           50};          // ps
parameter int tWLH = tWLS[ddr_sg];
parameter int tRRDt      [NUM_SG] = '{10.0*KI,    10.0*KI,    10.0*KI,    10.0*KI,      10.0*KI,      7.5*KI};      // ns
parameter int tJIT_max   [NUM_SG] = '{0.070*KI,   0.050*KI,   0.0467*KI,  0.040*KI,     0.040*KI,     0.040*KI};    // ns
parameter int tWLS_SE             = 0.250*KI;                                                                       // ns
parameter int tWLH_SE             = tWLS_SE;



////////////////////////////////////////////////////////////////////////
  
   `define   tRFCab     (130.0*KI)  
   `define   tRFCpb     (60.0 *KI)  

// Clock Timing
   `define   tCKmin      (0.535*KI)          // ps        
  
// Write Timing
   `define   tWPREminc        1.8            // tCK


// Command Address Input Timing
   `define   tCIVW            0.3            //tck(avg)  
   `define   tIPWc            0.7
   `define   tCIVW_SE        0.35            // UI=tCK

   
   
// Command Address Input Timing
   `define   tCIPW            0.55            // tCK

// Asynchronous ODT Turn On and Turn Off Timing
   `define   tODTonmin        (1.50*KI)          // ps
   `define   tODTonmint       (1.50*KI)           // ps
   `define   tODTonmaxt       (3.50*KI)           // ps
   `define   tODToffmint      (1.50*KI)           // ps
   `define   tODToffmaxt      (3.50*KI)           // ps



//---  Special parameter ---//

// CA Bus Training Parameters  
   `define   tCKPSTCSc              5              //tck
   `define   tCKPSTCSt              (7.50*KI)        //ps

// ============================
// Parameter for all speed     
// ============================


// Initialization Timing Parameters
  `define   tINIT0          (20000000*KI)        // 20ms
  `define   tINIT1          (200*MI)        // us
																	   
  `define   tINIT2          (10*KI)         // ns
  `define   tINIT3          (2*GI)          // ms
  `define   tINIT4          5               // 5tCK
  `define   tINIT5          (2*MI)          // us
  `define   tPW_RESET       (100*KI)        // ns



//ZQ Calibration Parameters
  `define   tZQCAL          (1*MI)          // us
  `define   tZQLATt         (30*KI)         // ns
  `define   tZQLATc         8               // tCK               


//ZQ Calibration Parameters
   `define   tZQRESETt             (50.0*KI)
   `define   tZQRESETc             3 


// Speed Grade                       SG1600,  SG2400,   SG2667,   SG3200,   SG3733,   SG4267
parameter int TCK_MIN  [NUM_SG] = '{1.25*KI,    0.83*KI,     0.75*KI,     0.625*KI,    0.536*KI,    0.469*KI};      //clock period


// Clock Timing
   `define   tCKmax                (100.0*KI)      // ns         
   `define   tCHmin                0.43            // tCK         
   `define   tCHmax                0.57            // tCK        
   `define   tCLmin                0.43            // tCK         
   `define   tCLmax                0.57            // tCK     


// Refresh Requirement Parameters (per density)
   `define   tREFW                 (32000000.0*KI)            // 32ms
   `define   R                     8192      

   `define   tREFIab               (3904.0*KI)               
   `define   tREFIpb               (488.0*KI)  




// Self Refresh Timing  ->  Core Timing Parameters  or  CKE Input Timing

// Read Output Timing

   //----------------------------------------------
   // Read timing (It adjusts if needed.)
   //----------------------------------------------
   `define   tDQSCK                (3.5*KI)
   `define   tDQSQ                 0.000
   `define   tRPRE                 1.8         // tCK
   `define   tRPST                 0.4         // tCK
   // ----------------------------------------

   `define   tDQSCKmin             (1.50*KI)
   `define   tDQSCKmax             (3.50*KI)
   `define   tDQSCKmaxt            (3.50*KI)    

   `define   tDQSQmin              0.000       //  tCK
   `define   tDQSQmax              0.18        //  tCK
   `define   tRPREmin              1.8             
   `define   tRPSTmin              0.4             
   `define   tRPSTmax              1.4             


   //----------------------------------------------
   // Write timing (It adjusts if needed.)
   //----------------------------------------------
   `define   tDQS2DQ                   (0.50 *KI)           // 500ps
   `define   tDQS2DQ_min               (0.20 *KI)           // 200ps
   `define   tDQS2DQ_max               (0.80 *KI)           // 800ps
   
   `define   tDQSS                 1               // tCK
  
   //----------------------------------------------

   `define   tDIVWmint             (0.0780*KI)         // 78ps
   `define   tDIPW                 0.225           // tCK (0.45 UI)

   `define   tDQSS_u               `tDQSS
   `define   tDQSS_l               `tDQSS

   `define   tDQSSminc             0.75   //tck
   `define   tDQSSmaxc             1.25   //tck  
   `define   tDQSSmaxc_ru          2               // 1.25nCK -> 2nCK (RU)

   `define   tWPREc                2.0             // tCK 
   
   `define   tDQS2DQmin            (0.200*KI)
   `define   tDQS2DQmax            (0.800*KI)    
   `define   tDQSHminc             0.4         
   `define   tDQSLminc             0.4         
   `define   tDSSminc              0.2
   `define   tDSHminc              0.2

   `define   tWPSTmin1             0.4
   `define   tWPSTmin2             1.4
   `define   tWPREmin              1.8
   `define   tWPRE_tck             2.0

// CKE Input Timing
   `define	tCKEc	                  4
   `define	tCKEt	                  (7.50*KI) 
   `define	tCMDCKEc	              3
   `define	tCMDCKEt	              (1.750*KI)           
   `define	tCKELCKc	              5             //tck
   `define	tCKELCKt	              (5.0*KI)        //ps    
   `define  tCSCKE                    (1.750*KI)        
   `define  tCKELCSc                  5               
   `define  tCKELCSt                  (5.0*KI)
   `define	tCKCKEHc	              3            //tck   
   `define	tCKCKEHt	              (1.750*KI)     //ns   
 
   `define  tCSCKEH                   (1.750*KI)           
   `define  tCKEHCSc                  (5)               
   `define  tCKEHCSt                  (7.50 *KI)          
   `define  tMRWCKELc                 (10      )        
   `define  tMRWCKELt                 (14.0 *KI)           
   `define  tZQCKEc                   (3       )        
   `define  tZQCKEt                   (1.750*KI)

// SELF Input Timing
   `define	tESCKEc	              3
   `define	tESCKEt	              (1.750*KI)


// Boot Timing Parameters
   `define   tCKbmin               (18.0*KI)           
   `define   tCKbmax               (100.0*KI)           
   `define   tISb                  (0.0    )         
   `define   tIHb                  (0.0    )         
   `define   tDQSCKb_min           (1.0 *KI)            
   `define   tDQSCKb_max           (10.0*KI)

//Core Timing Parameters    
   `define   tSRc                  (3             ) //tck
   `define   tSRt                  (15.0*KI       ) //ps 
   `define   tXSRc                 (2             ) //tck         
   `define   tXSRt                 (`tRFCab+7.5*KI) //ps  
   `define   tXPc                  (5             ) //tck 
   `define   tXPt                  (7.50 *KI      ) //ps  
   `define   tCCD                  (8             ) //tck
   `define   tRTPt                 (7.50*KI       ) //ps 
   `define   tRTPc                 (8             ) //tck
   `define   tRCDt                 (18.0*KI       ) //ps
   `define   tRCDc                 (4             ) //tck
   `define   tCCDMW                (32*KI         ) //ps   
   `define   tRPpbt                (18.0*KI       ) //ps    
   `define   tRPpbc                (4             ) //tck            
   `define   tRPabt                (21.0*KI       )  //ps  
   `define   tRPabc                (4             )   //tck   
   `define   tRASt_max             (70200.0*KI    )
   `define   tRASt_min             (42.0*KI       )
   `define   tRASc_min             (3             )
   `define   tWRc                  (6             )
   `define   tWRt                  (18.0 *KI      )
   `define   tWRt1                 (16.0*KI)       // ns, SCL-1=18+16
   `define   tWTRc                 8    
   `define   tWTRt                 (10.0 *KI) 
   `define   tRRDc                 (4       )      //tck
   `define   tPPD                  (4       )      //tck
   `define   tFAW                  (40*KI   )      //ps 
   `define   tFAW_4267             (30*KI   )      //ps
   `define   tFAW_other            (40*KI   )      //ps 
  
  
// Mode Register Timing Parameters
   `define   tMRWc	               (10      )      //tck                                        
   `define   tMRWt	               (10.0*KI )       //ps                              
   `define   tMRR	               (8       )      //tck                            

   
   `define   tSDOc    	           12                                              
   `define   tSDOt    	           (20*KI)                      
                                      

// CA Bus Training Parameters
   `define   tDStrain              (2*KI)         
   `define   tDHtrain              (2*KI)         

   `define   tADR                  (2*KI)             
   `define   tADRmax               (20*KI)           

   `define   tCACDt                (20.0*KI)       
   `define   tDQSCKEt              (10.0*KI)       
   `define   tDQSCKEc               0       
   `define   tCAENTt               (250.0*KI)    
   `define   tVREFca_Long          (250.0*KI)
   `define   tVREFca_Middle        (200.0*KI)    
   `define   tVREFca_Short         (80.0*KI)
   `define   tVREFca_cbt_Short     (80.0*KI)
   `define   tCS_VREF               2
   `define   tCKEHDQS              (10.0*KI)        
   `define   tMRZ                  (1.50*KI)        
   `define   tCKELODTon            (20*KI)
   `define   tCKELODToff           (20*KI)

   `define   tXCBT_Short           (200.0*KI)
   `define   tXCBT_Middle          (200.0*KI)
   `define   tXCBT_Long            (250.0*KI)
   `define   tXCBTc                5
   
   
// VRCG Parameters
   `define   tVRCG_ENABLE          (200.0*KI)
   `define   tVRCG_DISABLE         (100.0*KI)


// Frequency Set-Point Parameters
   `define   tCKFSPEt              (7.50*KI )       
   `define   tCKFSPEc              (4       )     
   `define   tCKFSPXt              (7.50*KI )      
   `define   tCKFSPXc              (4       )     
   `define   tFC_short             (200.0*KI)
   `define   tFC_middle            (200.0*KI)
   `define   tFC_long              (250.0*KI)
   `define   tMRW_PSTc              2            //tck //2021.9.12 add

// Write Leveling Parameters
   `define   tWLMRD                40            //tck       
   `define   tWLWPRE               20            //tck       
   `define   tWLDQSEN              20            //tck       
   `define   tWLOt_min             0.0           
   `define   tWLOt_max             (20.0*KI)       //ps          
   `define   tMRDc	               (10     )       //tck                            
   `define   tMRDt	               (14.0*KI)       //ps                               
   `define   tCKPRDQSc	           (4      )       //tck                                 
   `define   tCKPRDQSt	           (7.50*KI)       //ps                                        
   `define   tCKPSTDQSc	           (4      )       //tck                          
   `define   tCKPSTDQSt	           (7.50*KI)       //ps                                      

   
// DQS Oscillator Matching Error Specification
   `define   tOSCOt                (40.0*KI) 
   `define   tOSCOc                8 


// Temperature Derating Parameters
   `define   tDQSCKdmax            3.50    + 0.100       // + 0.100 ns
   `define   tRCdt                 63.0    + 3.750       // + 3.750 ns
   `define   tRCDdt                18.000  + 1.875       // + 1.875 ns
   `define   tRPabdt               21.000  + 1.875       // + 1.875 ns
   `define   tRPpbdt               18.000  + 1.875       // + 1.875 ns
   `define   tRASdt_min            42.000  + 1.875       // + 1.875 ns
   `define   tRRDdt                10.00   + 1.875       // + 1.875 ns



// Internal VREF(DQ) Specifications
   `define   tVref_time_Short      (100.0*KI    )              
   `define   tVref_time_Middle     (200.0*KI    )
   `define   tVref_time_Long       (250.0*KI    )
   `define   tVref_time_Weak       (1000000.0*KI)             // 1 ms               

// Post-Package Repair Timing Parameters
   `define   tPGM          (1000*KI*KI*KI)
   `define   tPGM_Exit     (15.0*KI      )
   `define   tPGMPST       (50.0*KI*KI   )            


// Another
   `define   Read_Interval         167000000.0             // 167 ms
   `define   time_plus             0.0001                  // 100 fs

   `define   MASK_WRIT_BL          16                      // BL 16 only
   `define   MRR_BL                16                      // BL 16 only
   `define   MPC_BL                16                      // BL 16 only


// LPDDR4 Configuration of per channel  

   `define   WL_max           34 
   `define   BL_max           32 
   `define   MPC_BL_max       16   
   `define   nRTP_max         16 
   `define   nWR_max          40 
   `define   ErrorStop_Cyc    10
   `define   RL_max        40 
  
   `define  L 1'b0 
   `define  H 1'b1 
   `define  X 1'bx 
   `define  Z 1'bz        
 
   
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Timing parameters 


    parameter  TCK_600MHz= 1.67*KI;  // (ns);  

	
	parameter  MAX_BITS        =     `bank_wid+ `row_wid +`col_wid; 
	
// Simulation parameters
    parameter MSGLENGTH         =        256; // max length in characters of a debug string
   
     
    //lpddr4 command decode	 
    // ca[5:0] 
    // X means H or L (but a defined logic level)

    parameter
	          //1 clock command
	          DES_CMD           =   6'bxxxxxx,    
			  
			  //2 clock command, 1st is the command, 2nd is the op code
              MPC_CMD           =   5'b00000, //ca[4:0], ca[5]:op6
              PRE_CMD           =   5'b10000, //ca[4:0], ca[5]:ab
			  REF_CMD           =   5'b01000, //ca[4:0], ca[5]:ab
			  REF_ALL_BANK_CMD  =   5'b01001, //ca[4:0], ca[5]:ab
			  REF_PER_BANK_CMD  =   5'b01010, //ca[4:0], ca[5]:ab
              SRE_CMD           =   5'b11000, //ca[4:0], ca[5]:V
              WR1_CMD           =   5'b00100, //ca[4:0], ca[5]:bl
              SRX_CMD           =   5'b10100, //ca[4:0], ca[5]:V
              MASK_WR1_CMD      =   6'b001100, //ca[5:0]
			  RD1_CMD           =   5'b00010, //ca[4:0], ca[5]:bl
              CAS2_CMD          =   5'b10010, //ca[4:0], ca[5]:C8
              MRW1_CMD          =   5'b00110, //ca[4:0], ca[5]:OP7
              MRW2_CMD          =   5'b10110, //ca[4:0], ca[5]:OP6
              MRR1_CMD          =   5'b01110, //ca[4:0], ca[5]:V
              ACT1_CMD          =   2'b01,  //2bits
              ACT2_CMD          =   2'b11,  //2bits
              
			  //complete command
			  C_ACT_CMD                 = 6'b000000,
			  C_READ_CMD                = 6'b000001,
			  C_WRITE_CMD               = 6'b000010,
			  C_MPC_CMD                 = 6'b000011,
			  C_MRR_CMD                 = 6'b000100,
			  C_MRW_CMD                 = 6'b000101,
			  C_PRE_CMD                 = 6'b000110,
			  C_REF_CMD                 = 6'b000111,
			  C_MASK_WRITE_CMD          = 6'b001000,
			  C_SRE_CMD                 = 6'b001001,
			  C_SRX_CMD                 = 6'b001010,
			  C_MPC_WR_FIFO_CMD         = 6'b001011,
              C_MPC_RD_FIFO_CMD         = 6'b001100, 
			  C_MPC_DQS_START_OSCI_CMD  = 6'b001101, 
			  C_MPC_DQS_STOP_OSCI_CMD   = 6'b001110, 
              C_MPC_DQ_CALIB_CMD        = 6'b001101, 
			  C_MPC_STAT_ZQ_CAL_CMD     = 6'b001110, 
			  C_MPC_STAT_ZQ_LAT_CMD     = 6'b011110, 
			  C_PWDN_ENTER              = 6'b001111,
			  C_PWDN_EXIT               = 6'b010000,
			  C_REF_ALL_BANK_CMD        = 6'b010001,
              C_REF_PER_BANK_CMD        = 6'b010110,
              C_WRITE_AP_CMD            = 6'b010111,
              C_READ_AP_CMD             = 6'b011000,  			  
		      C_CAS2_CMD                = 6'b011001,  
			   
			   
			  //1st cycle command
			  C_ACT_1st_CMD                 = 6'b100000,
			  C_READ_1st_CMD                = 6'b100001,
			  C_WRITE_1st_CMD               = 6'b100010,
			  C_MPC_1st_CMD                 = 6'b100011,
			  C_MRR_1st_CMD                 = 6'b100100,
			  C_MRW_1st_CMD                 = 6'b100101,
			  C_PRE_1st_CMD                 = 6'b100110,
			  C_REF_1st_CMD                 = 6'b100111,
			  C_MASK_WRITE_1st_CMD          = 6'b101000,
			  C_SRE_1st_CMD                 = 6'b101001,
			  C_SRX_1st_CMD                 = 6'b101010,
			  C_MPC_WR_FIFO_1st_CMD         = 6'b101011,
              C_MPC_RD_FIFO_1st_CMD         = 6'b101100, 
			  C_MPC_DQS_START_OSCI_1st_CMD  = 6'b101101, 
			  C_MPC_DQS_STOP_OSCI_1st_CMD   = 6'b101110, 
              C_MPC_DQ_CALIB_1st_CMD        = 6'b101111,  
			  C_ACT2_1st_CMD                = 6'b110000, 
			  C_CAS2_1st_CMD                = 6'b110001;  
			   
			   
        
// MA mode register address and bit definition following
    parameter
	          //LPDDR4 configuration bits
			  //MR0 ,readonly, Device  information
			  MR0_addr =8'h00,
              MR0_BIT0_REF_BOTH   = 1'b0,
              MR0_BIT0_REF_ONLY   = 1'b1, 
 
              MR0_BIT43_RZQ_notexecute     =2'b00,
  			  MR0_BIT43_RZQ_ZQPin_VSSQ     =2'b01, 
			  MR0_BIT43_RZQ_ZQpin_VDDQ     =2'b10,
			  MR0_BIT43_RZQ_ZQpin_complete =2'b11,
			 
			  
			  MR0_BIT7_CATR_NOT_TERM      = 1'b0,   
	          MR0_BIT7_CATR_TERM          = 1'b1,  
			  
			  
			  //MR1, write ony, device feature 1
			  MR1_addr =8'h01,
			  
			  MR1_BIT10_BL16          = 2'b00, //default, BL=16 sequential
			  MR1_BIT10_BL32          = 2'b01, //       , BL=32 sequential
			  MR1_BIT10_BL_ONTHEFLY   = 2'b10, //BL=16 or BL32 on the fly			  
			  
			  
			  MR1_BIT2_WR_PRE         = 1'b1,  //write preamble 2tck			  
			  
			  MR1_BIT3_RD_PRE_STA         = 1'b0, //default, static 
			  MR1_BIT3_RD_PRE_TOG         = 1'b1, // toggle
			  
			  MR1_BIT64_nWR_6   = 3'b000, //default
			  MR1_BIT64_nWR_10  = 3'b001, 
			  MR1_BIT64_nWR_16  = 3'b010, 
			  MR1_BIT64_nWR_20  = 3'b011,  
			  MR1_BIT64_nWR_24  = 3'b100, 
			  MR1_BIT64_nWR_30  = 3'b101, 
			  MR1_BIT64_nWR_34  = 3'b110, 
			  MR1_BIT64_nWR_40  = 3'b111, 
			  
			  
			  MR1_BIT7_RD_PST_0P5TCK   = 1'b0, //default 
			  MR1_BIT7_RD_PST_1P5TCK   = 1'b1,  
			  
			  
			  //MR2, write ony, device feature 2
			  MR2_addr =8'h02,
		      //read latency	  
 			  //DBI disable, MR3[6]=0;
			 
			  MR2_BIT20_RL6_RTP8_DBI_DIS   = 3'b000, // default
			  MR2_BIT20_RL10_RTP8_DBI_DIS  = 3'b001, //
			  MR2_BIT20_RL14_RTP8_DBI_DIS  = 3'b010, //
			  MR2_BIT20_RL20_RTP8_DBI_DIS  = 3'b011, //
			  MR2_BIT20_RL24_RTP10_DBI_DIS = 3'b100, //
			  MR2_BIT20_RL28_RTP12_DBI_DIS = 3'b101, //
			  MR2_BIT20_RL32_RTP14_DBI_DIS = 3'b110, //
			  MR2_BIT20_RL36_RTP16_DBI_DIS = 3'b111, //
			  
			  //DBI enable, MR3[6]=1;
			  MR2_BIT20_RL6_RTP8_DBI_ENA   = 3'b000, //
			  MR2_BIT20_RL12_RTP8_DBI_ENA  = 3'b001, //
			  MR2_BIT20_RL16_RTP8_DBI_ENA  = 3'b010, //
			  MR2_BIT20_RL22_RTP8_DBI_ENA  = 3'b011, //
			  MR2_BIT20_RL28_RTP10_DBI_ENA = 3'b100, //
			  MR2_BIT20_RL32_RTP12_DBI_ENA = 3'b101, //
			  MR2_BIT20_RL36_RTP14_DBI_ENA = 3'b110, //
			  MR2_BIT20_RL40_RTP16_DBI_ENA = 3'b111, //
		
			  //write latency
			  //setA, mr2[6]=0;
			  MR2_BIT53_WL4_SETA    = 3'b000, //default
			  MR2_BIT53_WL6_SETA    = 3'b001, //
			  MR2_BIT53_WL8_SETA    = 3'b010, //
			  MR2_BIT53_WL10_SETA   = 3'b011, //
			  MR2_BIT53_WL12_SETA   = 3'b100, //
			  MR2_BIT53_WL14_SETA   = 3'b101, //
			  MR2_BIT53_WL16_SETA   = 3'b110, //
			  MR2_BIT53_WL18_SETA   = 3'b111, //
		
		      //setB, mr2[6]=1
			  MR2_BIT53_WL4_SETB    = 3'b000, //
			  MR2_BIT53_WL8_SETB    = 3'b001, //
			  MR2_BIT53_WL12_SETB   = 3'b010, //
			  MR2_BIT53_WL18_SETB   = 3'b011, //
			  MR2_BIT53_WL22_SETB   = 3'b100, //
			  MR2_BIT53_WL26_SETB   = 3'b101, //
			  MR2_BIT53_WL30_SETB   = 3'b110, //
			  MR2_BIT53_WL34_SETB   = 3'b111, //
		
			  
			
			  
			  MR2_BIT6_WL_select_A  = 1'b0,  //default
			  MR2_BIT6_WL_select_B  = 1'b1, 
			  
			  MR2_BIT7_WL_LEVEL_DIS  = 1'b0, //default
			  MR2_BIT7_WL_LEVEL_ENA  = 1'b1, 
			


			
			  //MR3 , write only, I/O configuration 1
			  MR3_addr =8'h03,
			  
			  MR3_BIT0_PU_CAL_2P5 = 1'b0,
			  MR3_BIT0_PU_CAL_3P0 = 1'b1, //default
			  
			  MR3_BIT1_WR_PST_0P5 = 1'b0, //default
			  MR3_BIT1_WR_PST_1P5 = 1'b1, 
			 
              MR3_BIT2_PPRP_DIS = 1'b0, //default
			  MR3_BIT2_PPRP_ENA = 1'b1,
			  
			  
			  MR3_BIT53_PDDS_RZQ_DIV1 = 3'b001,
			  MR3_BIT53_PDDS_RZQ_DIV2 = 3'b010,
			  MR3_BIT53_PDDS_RZQ_DIV3 = 3'b011,
			  MR3_BIT53_PDDS_RZQ_DIV4 = 3'b100,
			  MR3_BIT53_PDDS_RZQ_DIV5 = 3'b101,
			  MR3_BIT53_PDDS_RZQ_DIV6 = 3'b110, //default
			  
			  MR3_BIT6_DBI_RD_DIS      = 1'b0, //default
			  MR3_BIT6_DBI_RD_ENA      = 1'b1, 
			  
			  MR3_BIT7_DBI_WR_DIS      = 1'b0, //default
			  MR3_BIT7_DBI_WR_ENA      = 1'b1, 
			  
			  
			  //MR4, read only, device temperature
			  MR4_addr =8'h04,
			  
			  MR4_BIT20_low_temp  = 3'b000,
			  MR4_BIT20_4xtref    = 3'b001,
			  MR4_BIT20_2xtref    = 3'b010,
			  MR4_BIT20_1xtref    = 3'b011, //default
			  MR4_BIT20_half_tref = 3'b100,
			  MR4_BIT20_qrtr_not_derate_tref = 3'b101,
			  MR4_BIT20_qrtr_do_derate_tref = 3'b110,
			  MR4_BIT20_high_temp  = 3'b111,
			  
			  MR4_BIT3_SR_ABORT_DIS = 1'b0, //default
			  MR4_BIT3_SR_ABORT_ENB = 1'b1,
			  
			  MR4_BIT4_PPRE_EXIT = 1'b0, //default
			  MR4_BIT4_PPRE_ENTER = 1'b1,
		
              MR4_BIT65_TERMAL_OFFSET_NO = 2'b00, //default 		
			  MR4_BIT65_TERMAL_OFFSET_5DG = 2'b01, // 5degree
			  MR4_BIT65_TERMAL_OFFSET_10DG= 2'b10, //10 degree
			  
			  MR4_BIT7_TUF_NO_CHANGE  = 1'b0, //default
			  MR4_BIT7_TUF_CHANGE     = 1'b1,
			  
			  //MR5 ,  read only, basic configuration 1
			  MR5_addr =8'h05,
			  MR5_BIT70_Manufacturer_winbond = 8'b00001000, 

               //MR6 ,  read only, basic configuration 2
              MR6_addr =8'h06,  			  
			  
			  MR6_BIT70_revision   = 8'b00000000, //winbond

			  
			  //MR7 revision ID2
			  MR7_addr =8'h07,  	
              MR7_BIT70_revision   = 8'b00000000, //winbond  ??V1.1 NO.10
			   
               //MR8 ,  read only, basic configuration 4
			   MR8_addr =8'h08,

			   MR8_BIT10_ram_type_S16   = 2'b00, //S16 SDRAM
 
               MR8_BIT52_density_1Gb = 4'b1100,       //wibond
               MR8_BIT52_density_2Gb = 4'b0000,        
               MR8_BIT52_density_4Gb = 4'b0010,
			 
			   
			  
               MR8_BIT76_IO_width_x16 = 2'b00, //default 

                MR9_addr =8'h09,
        
               //MR10, write only , calibration code
			   MR10_addr = 8'h0A,
			   
			   MR10_BIT0_ZQ_RESET_NORMAL  = 1'b0, //default
			   MR10_BIT0_ZQ_RESET_RESET   = 1'b1,
			   
               //M11, write only, ODT control
			   MR11_addr = 8'h0B,
			   
			   MR11_BIT20_DQ_ODT_DIS      = 3'b000, //default 
			   MR11_BIT20_DQ_ODT_RZQ_DIV1 = 3'b001,
			   MR11_BIT20_DQ_ODT_RZQ_DIV2 = 3'b010,
			   MR11_BIT20_DQ_ODT_RZQ_DIV3 = 3'b011,
			   MR11_BIT20_DQ_ODT_RZQ_DIV4 = 3'b100,
			   MR11_BIT20_DQ_ODT_RZQ_DIV5 = 3'b101,
			   MR11_BIT20_DQ_ODT_RZQ_DIV6 = 3'b110,
			   
			   MR11_BIT64_CA_ODT_DIS      = 3'b000, //derfault
			   MR11_BIT64_CA_ODT_RZQ_DIV1 = 3'b001,
			   MR11_BIT64_CA_ODT_RZQ_DIV2 = 3'b010,
			   MR11_BIT64_CA_ODT_RZQ_DIV3 = 3'b011,
			   MR11_BIT64_CA_ODT_RZQ_DIV4 = 3'b100,
			   MR11_BIT64_CA_ODT_RZQ_DIV5 = 3'b101,
			   MR11_BIT64_CA_ODT_RZQ_DIV6 = 3'b110,
			   
			   
		       //MR12 registers information, lpddr4
			   MR12_addr = 8'h0C,
			   
			   MR12_BIT50_VREFCA_SETTING      =  6'b001101,  //6'b00000 ~ 6'b110010
			   MR12_BIT6_VREFCA_RANGE0_ENA    =  1'b0, 
			   MR12_BIT6_VREFCA_RANGE1_ENA    =  1'b1, //default
			  
			  
			   //MR13 registers control, lpddr4
			   MR13_addr = 8'h0D,
			  
			   //command bus training
			   MR13_BIT0_CBT_DIS   = 1'b0, //deafult
 			   MR13_BIT0_CBT_ENA   = 1'b1, //training enable
 			   
			   //read preamble training
			   MR13_BIT1_RPT_DIS    = 1'b0, //deafult
 			   MR13_BIT1_RPT_ENA    = 1'b1, //training enable
 			  
			   //VREF output
			   MR13_BIT2_VRO_DIS    = 1'b0, //deafult
 			   MR13_BIT2_VRO_ENA    = 1'b1, //training enable
 			  
			   //VREF current generator
			   MR13_BIT3_VRCG_NORMAL    = 1'b0, //deafult
 			   MR13_BIT3_VRCG_FAST      = 1'b1, //fast response
 			  
			   //refresh rate option 
			   MR13_BIT4_RRO_DIS    = 1'b0, //deafult
 			   MR13_BIT4_RRO_ENA    = 1'b1, //        MR4[2:0] 			  
			  
			   //data mask disable
			   MR13_BIT5_DMD_ENA    = 1'b0, //deafult
 			   MR13_BIT5_DMD_DIS    = 1'b1, //
 			  
			  
			   //frequency set point write enable
			   MR13_BIT6_FSP_WR_POINT0    = 1'b0, //deafult
 			   MR13_BIT6_FSP_WR_POINT1    = 1'b1, //
 			  
			  
			   //frequency set point operation mode
			   MR13_BIT7_FSP_OP_POINT0    = 1'b0, //deafult
 			   MR13_BIT7_FSP_OP_POINT1    = 1'b1, //
 			  
			  //MR14 registers information, lpddr4
			   MR14_addr = 8'h0E,
			   
			   MR14_BIT50_VREFDQ_SETTING      =  6'b001101,  //6'b00000 ~ 6'b110010
			   MR14_BIT6_VREFDQ_RANGE0_ENA    =  1'b0, 
			   MR14_BIT6_VREFDQ_RANGE1_ENA    =  1'b1, //default
 			  
			  
			  
			  //MR15 DBI LB,lower byte invert for DQ calibration, lpddr4
			   MR15_addr = 8'h0F,
			   
			   MR15_BIT70_DBI_LB      =  8'h55,   // default, 0: do not invert, 
			                                      //1: invert the DQ calibration pattern in MR32, MR40    
			   MR18_addr = 8'h12,
			  
			   MR19_addr = 8'h13,
			   
			  //MR20 DBI UB,upper byte invert for DQ calibration, lpddr4
			   MR20_addr = 8'h14,
			   
			   MR20_BIT70_DBI_UB      =  8'h55,   // default, 0: do not invert, 
			                                      //1: invert the DQ calibration pattern in MR32, MR40    
			   
			   MR22_addr = 8'h16,
			   MR22_BIT20_SOC_ODT_DIS      = 3'b000, //derfault
			   MR22_BIT20_SOC_ODT_RZQ_DIV1 = 3'b001,
			   MR22_BIT20_SOC_ODT_RZQ_DIV2 = 3'b010,
			   MR22_BIT20_SOC_ODT_RZQ_DIV3 = 3'b011,
			   MR22_BIT20_SOC_ODT_RZQ_DIV4 = 3'b100,
			   MR22_BIT20_SOC_ODT_RZQ_DIV5 = 3'b101,
			   MR22_BIT20_SOC_ODT_RZQ_DIV6 = 3'b110,
			   
			   
			   MR22_BIT3_ODT_CK_DIS = 1'b0,
			   MR22_BIT3_ODT_CK_ENA = 1'b1,
			   
			   MR22_BIT4_ODT_CS_DIS = 1'b0,
			   MR22_BIT4_ODT_CS_ENA = 1'b1,
			   
			   MR22_BIT5_ODT_CA_DIS = 1'b0,
			   MR22_BIT5_ODT_CA_ENA = 1'b1,
			  
			   
			   MR23_addr = 8'h17,
				
			   MR24_addr = 8'h18,									  
			  
			   MR25_addr = 8'h19,
			  
			   //MR32 DQ calibration pattern A
			   MR32_addr = 8'h20,
			   
			   MR32_BIT70_DQ_CALI_PATTERN_A      =  8'h5A,
			 
			    //MR40 DQ calibration pattern B
			   MR40_addr = 8'h28,
			   
			   MR40_BIT70_DQ_CALI_PATTERN_B      =  8'h3C,
			 
			  
			   MR51_addr = 8'h33, 
			   MR39_addr = 8'h27,
			   MR31_addr = 8'h1F,
			   MR30_addr = 8'h1E,
			   MR26_addr = 8'h1A,
			   MR21_addr = 8'h15,
			   MR17_addr = 8'h11,
			   MR16_addr = 8'h10;
			   
			  
			 //MPC command decode op[6:0]
	parameter		 
               MPC_RD_FIFO_CMD       =  7'b1000001,	 // CAS2		 
			   MPC_RD_DQ_CALIB_CMD   =  7'b1000011,  // CAS2
			   MPC_WR_FIFO_CMD       =  7'b1000111,  // CAS2
			   MPC_START_DQS_OSC_CMD =  7'b1001011,
               MPC_STOP_DQS_OSC_CMD  =  7'b1001101,
			   MPC_STAT_ZQ_CAL_CMD   =  7'b1001111,
			   MPC_LATCH_ZQ_CAL_CMD  =  7'b1010001; 
 			   
			  
	parameter		 
               MPC_RD_FIFO_CMD_T       =  6'b000001,	 // CAS2		 
			   MPC_RD_DQ_CALIB_CMD_T   =  6'b000011,  // CAS2
			   MPC_WR_FIFO_CMD_T       =  6'b000111,  // CAS2
			   MPC_START_DQS_OSC_CMD_T =  6'b001011,
               MPC_STOP_DQS_OSC_CMD_T  =  6'b001101,
			   MPC_STAT_ZQ_CAL_CMD_T   =  6'b001111,
			   MPC_LATCH_ZQ_CAL_CMD_T  =  6'b010001; 		  
			   
    parameter  MPC_NOP           =          0,
               MPC_NOT_NOP       =          1;			   
			  
			  
//  parameter     
  
              
    parameter RFF_BITS          = 16;
    parameter RFF_CHUNK         = 8 * ((RFF_BITS*2)/32 + ((RFF_BITS*2)%32 ? 1 : 0));
  
   
//  
    parameter BNK0              =          0,
              BNK1              =          1,
              BNK2              =          2,
              BNK3              =          3,
              BNK4              =          4,
              BNK5              =          5,
              BNK6              =          6,
              BNK7              =          7,
              
			  BANKS             =          8,  
			  
              AP0               =          0,
              AP1               =          1,
              PRE_NON_AB        =          0,
              PRE_AB1           =          1,
              PRE_AB0           =          0,
			
			  
              REF_AB            =          1,   // all banks
              REF_PB            =          0,   // per bank
			  
			  CACAL_control      =          2,   
			  
              fsp0               =          1'b0,
          	  fsp1               =          1'b1,		  
			  
			  VREF_CA_DQ_MINI= 6'b000000,
              VREF_CA_DQ_MAX = 6'b110010,
			  
			  VREF_CA_DQ_RANGE0= 1'b0,
              VREF_CA_DQ_RANGE1= 1'b1;
              
			  
			  
			  