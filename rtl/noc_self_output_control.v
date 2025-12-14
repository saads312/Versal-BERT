`timescale 1ns / 1ps                                                                                                                             
                                                                                                                                                  
 module noc_self_output_control (                                                                                                                 
     input wire clk,                                                                                                                              
     input wire rstn,                                                                                                                             
                                                                                                                                                  
     // External control                                                                                                                          
     input wire start,                                                                                                                            
     output reg done,                                                                                                                             
     output reg error,                                                                                                                            
                                                                                                                                                  
     // DMA control outputs                                                                                                                       
     output reg start_dma_attn,      // Read attention output                                                                                     
     output reg start_dma_weight,    // Read W_self_output weight                                                                                 
     output reg start_dma_residual,  // Read residual                                                                                             
     output reg start_dma_out,       // Write final output                                                                                        
                                                                                                                                                  
     // DMA status inputs                                                                                                                         
     input wire dma_attn_done,                                                                                                                    
     input wire dma_weight_done,                                                                                                                  
     input wire dma_residual_done,                                                                                                                
     input wire dma_out_done,                                                                                                                     
     input wire dma_attn_error,                                                                                                                   
     input wire dma_weight_error,                                                                                                                 
     input wire dma_residual_error,                                                                                                               
     input wire dma_out_error,                                                                                                                    
                                                                                                                                                  
     // Compute control                                                                                                                           
     output reg start_compute,                                                                                                                    
     input wire compute_done                                                                                                                      
 );                                                                                                                                               
                                                                                                                                                  
 endmodule