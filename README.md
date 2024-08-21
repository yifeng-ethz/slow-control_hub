# Slow-Control Hub IP

## IP Description

Name: Slow-Control Hub
Description: Interconnect SWB and FEB. Translate the Mu3e Slow-Control packet into Avalon Memory-Mapped transations. Support read/write in burst mode. Out-of-Order is not allowed.  
  
Version (_hw_tcl): 2.7.11  
Version (RTL): 3.1  
Version (qsys): 18.1  

## About Slow-Control Hub IP

This IP serves as the media layer translation between standard Mu3e SC Packet and Avalon Memory-Mapped (AVMM) transactions, which should be instantiated on the Frontend-Board (FEB).  
  
(SWB->FEB) Mu3e SC command from Switching-Board (SWB) is translated into AVMM read or write command.
(FEB->SWB) AVMM read or write respond is translated into Mu3e SC reply.
  
It features a backpressure fifo to queue the uplink Mu3e SC reply packet in order.  

$$
\usepackage{bytefield}
\begin{bytefield}{32}
        \bitheader{0-31}  \\
        \begin{rightwordgroup}{preamble}
            \bitbox{6}{000111} \bitbox{2}{SC} \bitbox{16}{FPGA ID} \bitbox{8}{header K28.5}
        \end{rightwordgroup} \\
        \bitbox{4}{-}\bitbox{1}{$\bar{M}$}\bitbox{1}{$\bar{S}$}\bitbox{1}{$\bar{T}$}\bitbox{1}{$\bar{R}$}\bitbox{24}{start address} \\ 
        \begin{rightwordgroup}{read}
            \bitbox{16}{-} \bitbox{16}{length}
        \end{rightwordgroup} \\
        \begin{rightwordgroup}{write}
            \bitbox{16}{-} \bitbox{16}{length} \\
            \bitbox{32}{data} \\
            \bitbox{32}{data}
        \end{rightwordgroup} \\
        \bitbox{24}{-} \bitbox{8}{trailer (K28.4)} \\
\end{bytefield}
$$
