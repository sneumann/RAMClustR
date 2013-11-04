#' ramclustR
#'
#' Main clustering function 
#'
#' This is the Details section
#'
#' @param filename character Filename of the nmrML to check
#' @param ms MS1 intensities =MSdata, 
#' @param idmsms =ms, 
#' @param idMSMStag character e.g. "02.cdf"
#' @param featdelim character e.g. ="_"
#' @param timepos numeric 2
#' @param st numeric no clue e.g. =5, 
#' @param sr numeric also no clue yet =5, 
#' @param maxt numeric again no clue =20, 
#' @param deepSplit boolean e.g. =FALSE, 
#' @param blocksize integer number of features (scans?) processed in one block  =1000,
#' @param mult numeric =10
#'
#' @return A vector with the numeric values of the processed data
#' @author Corey Broeckling
#' @export

ramclustR<- function(  ms=MSdata, 
                       idmsms=ms, 
                       idMSMStag="02.cdf", 
                       featdelim="_", 
                       timepos=2, 
                       st=5, 
                       sr=5, 
                       maxt=20, 
                       deepSplit=FALSE, 
                       blocksize=1000,
                       mult=10,
                       hmax=1.05,
                       sampNameCol=1,
                       collapse=TRUE,
                       mspout=TRUE, 
                       mslev=2 ) {
  
  require(ff)
  require(fastcluster)
  require(dynamicTreeCut)

  ##remove MSdata sets and save data matrix alone
  a<-Sys.time()
  if(is.na(sampNameCol)) {featcol<-1:ncol(MSdata)} else {
    featcol<-setdiff(1:(ncol(MSdata)), sampNameCol)}
  
  data1<-as.matrix(MSdata[,featcol])
  data2<-as.matrix(MSMSdata[,featcol])
  
  ##check to make sure data is mirrored between MS and idMSMS
  # stopifnot(dimnames(data1)[[2]]==dimnames(data2)[[2]])
  
  ##retention times and mzs vectors
  rtmz<-matrix(
    unlist(
      strsplit(dimnames(data1)[[2]], featdelim)
    ), 
    byrow=TRUE, ncol=2)
  
  times<-as.numeric(rtmz[,2])
  mzs<-as.numeric(rtmz[,1])
  rm(rtmz)  
  
  ##sort rt vector and data by retention time
  data1<-data1[,order(times)]
  data2<-data2[,order(times)]
  mzs<-mzs[order(times)]
  times<-times[order(times)]
  
  ##extract names (would like to be pulling from XCMS set instead...)
  featnames<-dimnames(data1)[[2]]
  sampnames<-MSdata[,1]
  
  ##establish some constants for downstream processing
  n<-ncol(data1)
  vlength<-(n*(n-1))/2
  nblocks<-floor(n/blocksize)
  
  ##create three empty matrices, one each for the correlation matrix, the rt matrix, and the product matrix
  ffcor<-ff(vmode="double", dim=c(n, n), init=0)
  gc()
  ffrt<-ff(vmode="double", dim=c(n, n), init=0)
  gc()
  ffmat<-ff(vmode="double", dim=c(n, n), init=1)
  gc()
  Sys.sleep((n^2)/10000000)
  gc()
  
  ##make list of all row and column blocks to evaluate
  eval1<-expand.grid(0:nblocks, 0:nblocks)
  names(eval1)<-c("j", "k")
  eval1<-eval1[which(eval1[,1]>=eval1[,2]),]
  bl<-nrow(eval1)
  
  
  RCsim<-function(bl)  {
    j<-eval1[bl,1]  
    k<-eval1[bl,2]
    startc<-1+(j*blocksize)
    if ((j+1)*blocksize > n) {
      stopc<-n} else {
        stopc<-(j+1)*blocksize}
    startr<-1+(k*blocksize)
    if ((k+1)*blocksize > n) {
      stopr<-n} else {
        stopr<-(k+1)*blocksize}
    if(startc<=startr) {
      temp<-round(exp(-(( (abs(outer(times[startr:stopr], times[startc:stopc], FUN="-"))))^2)/(2*(st^2))), digits=20 )
      #stopifnot(max(temp)!=0)
      ffrt[startr:stopr, startc:stopc]<- temp
      temp<-round (exp(-((1-(pmax(  cor(data1[,startr:stopr], data1[,startc:stopc]),
                                    cor(data1[,startr:stopr], data2[,startc:stopc]),
                                    cor(data2[,startr:stopr], data2[,startc:stopc])  )))^2)/(2*(sr^2))), digits=20 )		
      ffcor[startr:stopr, startc:stopc]<-temp
      temp<- 1-(ffrt[startr:stopr, startc:stopc])*(ffcor[startr:stopr, startc:stopc])
      ffmat[startr:stopr, startc:stopc]<-temp
      gc()}
    gc()}
  
  
  ##Call the similarity scoring function
  system.time(sapply(1:bl, RCsim))
  #RCsim(bl=1:bl)
  
  b<-Sys.time()
  
  cat('\n','\n' )
  cat(paste("RAMClust feature similarity matrix calculated and stored:", 
            round(difftime(b, a, units="mins"), digits=1), "minutes"))
  
  #cleanup
  delete.ff(ffrt)
  rm(ffrt)
  delete.ff(ffcor)
  rm(ffcor)
  gc() 
  
  
  ##extract lower diagonal of ffmat as vector
  blocksize<-mult*round(blocksize^2/n)
  nblocks<-floor(n/blocksize)
  remaind<-n-(nblocks*blocksize)
  
  ##create vector for storing dissimilarities
  RC<-vector(mode="numeric", length=vlength)
  
  for(k in 0:(nblocks)){
    startc<-1+(k*blocksize)
    if ((k+1)*blocksize > n) {
      stopc<-n} else {
        stopc<-(k+1)*blocksize}
    temp<-ffmat[startc:nrow(ffmat),startc:stopc]
    temp<-temp[which(row(temp)-col(temp)>0)]
    if(exists("startv")==FALSE) startv<-1
    stopv<-startv+length(temp)-1
    RC[startv:stopv]<-temp
    gc()
    startv<-stopv+1
    rm(temp)
    gc()
  }    
  rm(startv)
  gc()
  
  ##convert vector to distance formatted object
  RC<-structure(RC, Size=(n), Diag=FALSE, Upper=FALSE, method="RAMClustR", Labels=featnames, class="dist")
  gc()
  
  c<-Sys.time()    
  cat('\n', '\n')
  cat(paste("RAMClust distances converted to distance object:", 
            round(difftime(c, b, units="mins"), digits=1), "minutes"))
  
  ##cleanup
  delete.ff(ffmat)
  rm(ffmat)
  gc()
  
  
  ##cluster using fastcluster package, average method
  system.time(RC<-hclust(RC, method="average"))
  gc()
  d<-Sys.time()    
  cat('\n', '\n')    
  cat(paste("fastcluster based clustering complete:", 
            round(difftime(d, c, units="mins"), digits=1), "minutes"))
  
  clus<-cutreeDynamicTree(RC, maxTreeHeight=hmax, deepSplit=deepSplit, minModuleSize=2)
  gc()
  
  
  RC$featclus<-clus
  RC$frt<-times
  RC$fmz<-mzs
  RC$nfeat<-as.vector(table(RC$featclus)[2:max(RC$featclus)])
  RC$nsing<-length(which(RC$featclus==0))
  
  e<-Sys.time() 
  cat('\n', '\n')
  cat(paste("dynamicTreeCut based pruning complete:", 
            round(difftime(e, d, units="mins"), digits=1), "minutes"))
  
  f<-Sys.time()
  cat('\n', '\n')
  cat(paste("RAMClust has condensed", n, "features into",  max(clus), "spectra in", round(difftime(f, a, units="mins"), digits=1), "minutes", '\n'))
  
  if(collapse=="TRUE") {
    cat('\n', '\n', "... collapsing features into spectra")
    wts<-colSums(data1[])
    RC$SpecAbund<-matrix(nrow=nrow(data1), ncol=max(clus))
    for (ro in 1:nrow(RC$SpecAbund)) { 
      for (co in 1:ncol(RC$SpecAbund)) {
        RC$SpecAbund[ro,co]<- weighted.mean(data1[ro,which(RC$featclus==co)], wts[which(RC$featclus==co)])
      }
    }
    g<-Sys.time()
    cat('\n', '\n')
    cat(paste("RAMClustR has collapsed feature quantities
             into spectral quantities:", round(difftime(g, f, units="mins"), digits=1), "minutes"))
  }
  
  RC$MSdata<-data1
  RC$MSMSdata<-data2
  rm(data1)
  rm(data2)
 
  gc()
  
#   if(mspout==TRUE){
#     cat(paste("writing msp formatted spectra..."))
#     source("mspout.R")
#     source("UPLC_C18params.R")
#     libName<-paste("spectra/", Experiment, ".mspLib", sep="")
#     file.create(file=libName)
#  
#     for (j in 1:max(RC$featclus)) {
#       for (m in 1:as.numeric(mslev)){ mspoutfun
#       }
#     }
#     
#     sapply(m=c(1:2), FUN=mspoutfun)
#         sapply(1:max(RC$featclus),  mspoutfun)      
#               }
#           }
#   }
    
    #source("mspout.R")
  if(mspout==TRUE){ 
    cat(paste("writing msp formatted spectra..."))
    source("R/UPLC_C18params.R")

    libName<-paste(Experiment, ".mspLib", sep="")
    file.create(file=libName)
    for (m in 1:as.numeric(mslev)){
        for (j in 1:max(RC$featclus)) {
          sl<-which(RC$featclus==j)
          wm<-vector(length=length(sl))
          if(m==1) {wts<-rowSums(RC$MSdata[,sl])
                    for (k in 1:length(sl)) {     
                      wm[k]<-weighted.mean(RC$MSdata[,sl[k]], wts)
                    }}
          if(m==2) {wts<-rowSums(RC$MSMSdata[,sl])
                    for (k in 1:length(sl)) {    
                      wm[k]<-weighted.mean(RC$MSMSdata[,sl[k]], wts)
                    }}
          mz<-RC$fmz[sl][order(wm, decreasing=TRUE)]
          rt<-RC$frt[sl][order(wm, decreasing=TRUE)]
          wm<-wm[order(wm, decreasing=TRUE)]
          mrt<-mean(rt)
          npeaks<-length(mz)
          for (l in 1:length(mz)) {
            ion<- paste(round(mz[l], digits=4), round(wm[l]))
            if(l==1) {specdat<-ion} 
            if(l>1)  {specdat<-c(specdat, " ", ion)}
          }
          cat(
            paste("Name: C", j, sep=""), '\n',
            paste("SYNON: $:00in-source", sep=""), '\n',
            paste("SYNON: $:04", sep=""), '\n', 
            paste("SYNON: $:05", if(m==1) {CE1} else {CE2}, sep=""), '\n',
            paste("SYNON: $:06", mstype, sep=""), '\n',
            paste("SYNON: $:07", msinst, sep=""), '\n',
            paste("SYNON: $:09", chrominst, sep=""), '\n',
            paste("SYNON: $:10", ionization, sep=""),  '\n',
            paste("SYNON: $:11", msmode, sep=""), '\n',
            paste("SYNON: $:12", colgas, sep=""), '\n',
            paste("SYNON: $:14", msscanrange, sep=""), '\n',
            paste("SYNON: $:16", conevolt, sep=""), '\n',
            paste("Comment: Rt=", round(mrt, digits=2), 
                  "  Contributor=\"Colorado State University Proteomics and Metabolomics Facility\"", 
                  "  Study=", Experiment, 
                  sep=""), '\n',
            paste("Num Peaks:", npeaks), '\n',
            paste(specdat), '\n', '\n', sep="", file=libName, append= TRUE)
        }
    }
    cat(paste('\n', "msp file complete", '\n')) 
  }  
  return(RC)
}