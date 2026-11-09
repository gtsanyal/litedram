/***********************************************************************************************
|*Company             : Winbond Electronics Corp. ("WINBOND")
|*Model Type          : Verilog Model
|*Product             : LPDDR4 SDRAM 
|*Part Number         : W66BP2NQ
***********************************************************************************************
|*Disclaimer :
|This model software code and all related notes or documentation (collectively "Software") is 
|provided "AS IS" without warranty of any kind. You bear the risk of using it. 
|Winbond Electronics Corp.("WINBOND") hereunder DISCLAIMS ALL WARRANTIES EXPRESS OR IMPLIED, 
|INCLUDING BUT NOT LIMITED TO, NONINFRINGEMENT OF THIRD PARTY RIGHTS, AND ANY IMPLIED WARRANTIES 
|OF MERCHANTABILITY OR FITNESS FOR ANY PARTICULAR PURPOSE. WINBOND DOES NOT WARRANT THAT THE 
|OPERATION OF THE SOFTWARE WILL BE UNINTERRUPTED OR ERROR-FREE. FURTHERMORE, WINBOND DOES NOT MAKE 
|ANY WARRANTIES REGARDING THE USE OR THE RESULTS OF THE USE OF THE SOFTWARE IN TERMS OF ITS 
|CORRECTNESS, ACCURACY, RELIABILITY, OR OTHERWISE. IN NO EVENT SHALL WINBOND, ITS SUBSIDIARY 
|COMPANIES OR THEIR SUPPLIERS BE LIABLE FOR ANY DIRECT, INDIRECT, CONSEQUENTIAL, INCIDENTAL, 
|OR SPECIAL DAMAGES (INCLUDING, WITHOUT LIMITATION, DAMAGES FOR LOSS OF PROFITS, 
|BUSINESS INTERRUPTION, OR LOSS OF 
|SOFTWARE, EVEN IF WINBOND HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.
| 
|Copyright :
|Copyright C 2024 Winbond Electronics Corp. All rights reserved. 
***********************************************************************************************/
timeunit 1ps; timeprecision 1ps;

module W66BP2NQ(
 
      CK_t_A,     CK_c_A, 
	  CK_t_B,     CK_c_B,                     //    Input
      CKE_A,      CKE_B,                     //    Input
      CS_A,       CS_B,                      //    Input
      CA_A,       CA_B,                      //    Input
      ODT_CA_A,   ODT_CA_B,                  //    Input
      DQ_A,       DQ_B,                      //    I/O
      DQS_t_A,    DQS_c_A, DQS_t_B, DQS_c_B, //    I/O
      DMI_A,      DMI_B,                     //     I/O
      RESET_n,                               //    Input
      ZQ                                     //    output
  );

`include "Config-AC.v"
//  DIR           WIDTH          PORT NAME
     input                   CK_t_A,     CK_c_A,  CK_t_B,  CK_c_B;
   input                   CKE_A,      CKE_B;
   input                   CS_A,       CS_B;  
   input [`ca_wid-1:0]     CA_A,       CA_B;
   input                   ODT_CA_A,   ODT_CA_B;       
   inout [`io_wid -1:0]    DQ_A,       DQ_B;        
   inout [`dqs_wid-1:0]    DQS_t_A,    DQS_c_A, DQS_t_B, DQS_c_B;
   inout [`dmi_wid-1:0]    DMI_A,      DMI_B;      
   input                   RESET_n;   
   output                  ZQ;       
   

W66AP6NB W66AP6NB_CHA(
         .ck        (  CK_t_A   ),
         .ck_n      (  CK_c_A   ),
         .cke       (  CKE_A    ),
         .cs_n      (  CS_A     ),
         .ca        (  CA_A     ),       
         .odt_ca    (  ODT_CA_A ),
         .dq        (  DQ_A     ),
         .dqs       (  DQS_t_A  ),
         .dqs_n     (  DQS_c_A  ),
         .dmi       (  DMI_A    ),
         .reset_n   (  RESET_n  ),
         .zq        (  ZQ       )       
   ); 

W66AP6NB W66AP6NB_CHB(
         .ck        (  CK_t_A   ),
         .ck_n      (  CK_c_A   ),
         .cke       (  CKE_A    ),
         .cs_n      (  CS_A     ),
         .ca        (  CA_A     ),       
         .odt_ca    (  ODT_CA_A ),
         .dq        (  DQ_A     ),
         .dqs       (  DQS_t_A  ),
         .dqs_n     (  DQS_c_A  ),
         .dmi       (  DMI_A    ),
         .reset_n   (  RESET_n  ),
         .zq        (  ZQ       )       
   ); 
endmodule
