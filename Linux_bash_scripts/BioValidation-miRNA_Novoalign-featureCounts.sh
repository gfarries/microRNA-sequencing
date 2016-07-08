##############################################################################
# miRNA-seq Biological Validation of Blood Serum from Field-infected Animals #
#        --- Linux bioinformatics workflow for known sense genes  ---        #
#             -- Method 1: Novoalign-featureCounts softwares --              #
##############################################################################
# Authors: Nalpas, N.C.; Correia, C.N. (2014) 
# Zenodo DOI badge: http://dx.doi.org/10.5281/zenodo.16164
# Version 1.2.0
# Last updated on: 07/07/2016

########################################################################
# Merge and uncompress miRNA-seq FASTQ files to be used with Novoalign #
########################################################################

# Unlike STAR, Novoalign doesn't accept multiple FASTQ files from different
# lanes. It also doesn't accept compressed files as input (unlicensed version).

# Create and enter temporary workiing directory:
mkdir $HOME/scratch/miRNAseqValidation/fastq_sequence/tmp
cd !$

# Create bash script to uncompress and merge trim.fast.gz from lanes
# 005 and 006 for each library:
for file in `find $HOME/scratch/miRNAseqValidation/fastq_sequence \
-name *_L005_R1_001_trim.fastq.gz`; \
do file2=`echo $file | perl -p -e 's/(_L005_)/_L006_/'`; \
sample=`basename $file | perl -p -e 's/(E\d+_)\w+_L\d+_R\d_\d*_trim.fastq.gz/$1/'`; \
echo "zcat $file $file2 > ${sample}trim.fastq" \
>> uncompress_merge.sh; \
done

# Run script:
chmod 755 uncompress_merge.sh
./uncompress_merge.sh

##############################################
# FastQC quality check of merged FASTQ files #
##############################################

# Required software is FastQC v0.11.5, consult manual/tutorial
# for details: http://www.bioinformatics.babraham.ac.uk/projects/fastqc/

# Create and enter working directory:
mkdir $HOME/scratch/miRNAseqValidation/quality_check/merged
cd !$

# Run FastQC in one file to see if it's working well:
fastqc -o $HOME/scratch/miRNAseqValidation/quality_check/merged \
--noextract --nogroup -t 2 \
$HOME/scratch/miRNAseqValidation/fastq_sequence/tmp/E10_trim.fastq

# Create bash script to perform FastQC quality check on all merged files:
for file in `find $HOME/scratch/miRNAseqValidation/fastq_sequence/tmp \
-name *trim.fastq`; do echo "fastqc --noextract --nogroup -t 2 \
-o $HOME/scratch/miRNAseqValidation/quality_check/merged $file" \
>> fastqc_merge.sh; \
done

# Run script on Stampede:
chmod 755 fastqc_merge.sh
nohup ./fastqc_merge.sh > fastqc_merge.sh.nohup &

# Check if all the files were processed:
more fastqc_merge.sh.nohup | grep "Failed to process file" \
>> failed_fastqc.txt

# Deleted all the HTML files:
rm -r *.html

# Check all output from FastQC:
mkdir tmp

for file in `ls *_fastqc.zip`; do unzip \
$file -d \
$HOME/scratch/miRNAseqValidation/quality_check/merged/tmp; \
done

for file in \
`find $HOME/scratch/miRNAseqValidation/quality_check/merged/tmp \
-name summary.txt`; do more $file >> reports_merged.txt; \
done

for file in \
`find $HOME/scratch/miRNAseqValidation/quality_check/merged/tmp \
-name fastqc_data.txt`; do head -n 10 $file >> basic_stats_merged.txt; \
done

# Remove temporary folder and its files:
rm -r tmp

################################################
# Alignment of miRNA-seq reads using Novoalign #
################################################

# Required software is Novoalign 3.04.06, consult manual for details:
# http://www.novocraft.com/downloads/V3.04.06/NovoalignReferenceManualV3.04.pdf

# Create and enter the Index reference genome directory:
mkdir -p /workspace/storage/genomes/bostaurus/UMD3.1_NCBI/Novoindex.3.4/
cd !$

# Index the reference genome using Novoalign:
nohup novoindex -t 3 \
/workspace/storage/genomes/bostaurus/UMD3.1_NCBI/Novoindex.3.4/Btau_UMD3.1_multi.ndx \
/workspace/storage/genomes/bostaurus/UMD3.1_NCBI/source_file/Btau_UMD3.1_multi.fa &

# Create and enter the alignment working directory:
mkdir -p $HOME/scratch/miRNAseqValidation/Novo-feature/alignment
cd !$

# Mapping reads from one FASTQ file to the indexed genome,
# to check if it works well:
nohup novoalign -d \
/workspace/storage/genomes/bostaurus/UMD3.1_NCBI/Novoindex.3.4/Btau_UMD3.1_multi.ndx \
-f $HOME/scratch/miRNAseqValidation/fastq_sequence/tmp/E10_trim.fastq \
-F ILM1.8 -t 30 -l 15 -s 1 -o SAM -m -e 50 -R 3 -r 'Exhaustive' 20 \
>> ./E10.sam &

# Create a bash script to perform alignment of individual samples FASTQ files
# against Bos taurus indexed genome:
for file in `ls $HOME/scratch/miRNAseqValidation/fastq_sequence/tmp/*_trim.fastq`; \
do outfile=`basename $file | perl -p -e 's/_trim\.fastq/\.sam/'`; \
echo "novoalign -d \
/workspace/storage/genomes/bostaurus/UMD3.1_NCBI/Novoindex.3.4/Btau_UMD3.1_multi.ndx \
-f $file -F ILM1.8 -t 30 -l 15 -s 1 -o SAM -m -e 50 -R 3 -r 'Exhaustive' 20 \
>> $HOME/scratch/miRNAseqValidation/Novo-feature/alignment/${outfile}" \
>> alignment.sh; \
done

# Split and run all scripts on Stampede
# (note: to allow loading in shared memory of the indexed genome wait 60sec
# between the first shell script job and the rest of them):
split -d -l 8 alignment.sh alignment.sh.
for script in `ls alignment.sh.*`
do
chmod 755 $script
nohup ./$script > ${script}.nohup &
if [ `echo $script` == 'alignment.sh.00' ]
then
sleep 60
fi
done






# Generate a master file containing Novoalign stats results
for file in `ls /home/nnalpas/scratch/miRNAseqTimeCourse/Novo-feature/alignment/*.nohup`; do grep -oP "\d{4}.*_trim\.fastq" $file | perl -p -e 's/^(\d{4}_.*)_trim.fastq/$1/' >> $HOME/scratch/miRNAseqTimeCourse/Novo-feature/alignment/filename.txt; grep "Read Sequences\:" $file | perl -p -e 's/\#\s*\w*\s\w*\:\s*(\d*)\s*/$1\n/' >> $HOME/scratch/miRNAseqTimeCourse/Novo-feature/alignment/inputread.txt; grep "Unique Alignment\:" $file | perl -p -e 's/\#\s*\w*\s\w*\:\s*(\d*)\s*.(\s*\d*\.\d*).*\s*/$1\t$2\n/' >> $HOME/scratch/miRNAseqTimeCourse/Novo-feature/alignment/unique.txt; grep "Multi Mapped\:" $file | perl -p -e 's/\#\s*\w*\s\w*\:\s*(\d*)\s*.(\s*\d*\.\d*).*\s*/$1\t$2\n/' >> $HOME/scratch/miRNAseqTimeCourse/Novo-feature/alignment/multi.txt; grep "No Mapping Found\:" $file | perl -p -e 's/\#\s*\w*\s\w*\s\w*\:\s*(\d*)\s*.(\s*\d*\.\d*).*\s*/$1\t$2\n/' >> $HOME/scratch/miRNAseqTimeCourse/Novo-feature/alignment/unmapped.txt; grep "Read Length\:" $file | perl -p -e 's/\#\s*\w*\s\w*\:\s*(\d*)\s*.(\s*\d*\.\d*).*\s*/$1\t$2\n/' >> $HOME/scratch/miRNAseqTimeCourse/Novo-feature/alignment/fail.txt; paste filename.txt inputread.txt unique.txt multi.txt unmapped.txt fail.txt > $HOME/scratch/miRNAseqTimeCourse/Novo-feature/alignment/novoalign.txt; done;
echo -e "Sample\tInput reads\tUniquely aligned reads\tPercentage uniquely aligned reads\tMulti mapped reads\tPercentage multi mapped reads\tUnmapped reads\tPercentage unmapped reads\tToo short reads\tPercentage too short reads" | cat - $HOME/scratch/miRNAseqTimeCourse/Novo-feature/alignment/novoalign.txt > $HOME/scratch/miRNAseqTimeCourse/Novo-feature/alignment/alignment.txt
rm -f filename.txt inputread.txt unique.txt multi.txt unmapped.txt fail.txt novoalign.txt


##########################################
# Count summarisation with featureCounts #
##########################################

# Use featureCounts to perform count summarisation; required package is featureCounts which is part of subread software, consult manual for details: http://bioinf.wehi.edu.au/subread-package/SubreadUsersGuide.pdf

# Create and enter the gene count summarisation directory for pre-miRNA
mkdir -p $HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/pre_miRNA
cd !$

# Run featureCounts with one sample to check if it is working fine:
featureCounts -a \
/workspace/storage/genomes/bostaurus/UMD3.1_NCBI/annotation_file/bta.gff3 \
-M --minOverlap 3 -s 1 -T 3 -t miRNA -g ID -o ./E10_counts.txt \
$HOME/scratch/miRNAseqValidation/Novo-feature/alignment/E10.sam

# Run featureCounts on SAM file containing multihits and uniquely mapped reads using stranded parameter
for file in `find $HOME/scratch/miRNAseqTimeCourse/Novo-feature/alignment/ \
-name *.sam`; do sample=`basename $file | perl -p -e 's/\.sam//'`; \
echo "mkdir \
$HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/pre_miRNA/$sample; \
cd $HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/pre_miRNA/$sample; \
featureCounts -a \
/workspace/storage/genomes/bostaurus/UMD3.1_NCBI/annotation_file/Btau_pre-miRNA.gtf \
-t exon -g gene_id -o $sample -s 1 -T 1 -M  --minOverlap 3 $file" \
>> count.sh; \
done

# Split and run all scripts on Stampede
split -d -l 35 count.sh count.sh.
for script in `ls count.sh.*`
do
chmod 755 $script
nohup ./$script > ${script}.nohup &
done

# Combine and check all output from featureCounts
for file in `find $HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/pre_miRNA -name *.summary`; do grep -oP "6.*\.sam" $file | perl -p -e 's/\.sam//' >> $HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/pre_miRNA/filename.txt; grep "Assigned" $file | perl -p -e 's/\w*\s*(\d*)/$1/' >> $HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/pre_miRNA/Assigned.txt ; grep "Unassigned_Ambiguity" $file | perl -p -e 's/\w*\s*(\d*)/$1/' >> $HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/pre_miRNA/Unassigned_Ambiguity.txt; grep "Unassigned_MultiMapping" $file | perl -p -e 's/\w*\s*(\d*)/$1/' >> $HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/pre_miRNA/Unassigned_MultiMapping.txt; grep "Unassigned_NoFeatures" $file | perl -p -e 's/\w*\s*(\d*)/$1/' >> $HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/pre_miRNA/Unassigned_NoFeatures.txt; grep "Unassigned_Unmapped" $file | perl -p -e 's/\w*\s*(\d*)/$1/' >> $HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/pre_miRNA/Unassigned_Unmapped.txt; paste filename.txt Assigned.txt Unassigned_Ambiguity.txt Unassigned_MultiMapping.txt Unassigned_NoFeatures.txt Unassigned_Unmapped.txt > $HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/pre_miRNA/featureCounts.txt; done;
echo -e "Sample\tAssigned reads\tUnassigned ambiguous reads\tUnassigned multi mapping reads\tUnassigned no features reads\tUnassigned unmapped reads" | cat - $HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/pre_miRNA/featureCounts.txt > $HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/pre_miRNA/Gene_count_stats.txt
rm -f filename.txt Assigned.txt Unassigned_Ambiguity.txt Unassigned_MultiMapping.txt Unassigned_NoFeatures.txt Unassigned_Unmapped.txt featureCounts.txt

# Note, run the next section only after the previous featureCounts jobs are done
# Create and enter the gene count summarisation directory for mature-miRNA
mkdir -p $HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/mature_miRNA
cd !$

# Run featureCounts on SAM file containing multihits and uniquely mapped reads using stranded parameter
for file in `find $HOME/scratch/miRNAseqTimeCourse/Novo-feature/alignment/ -name *.sam`; do sample=`basename $file | perl -p -e 's/\.sam//'`; echo "mkdir $HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/mature_miRNA/$sample; cd $HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/mature_miRNA/$sample; featureCounts -a /workspace/storage/genomes/bostaurus/UMD3.1_NCBI/annotation_file/Btau_mature-miRNA.gtf -t exon -g gene_id -o $sample -s 1 -T 1 -M --minReadOverlap 3 $file" >> count.sh; done;

# Split and run all scripts on Stampede
split -d -l 35 count.sh count.sh.
for script in `ls count.sh.*`
do
chmod 755 $script
nohup ./$script > ${script}.nohup &
done

# Combine and check all output from featureCounts
for file in `find $HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/mature_miRNA -name *.summary`; do grep -oP "6.*\.sam" $file | perl -p -e 's/\.sam//' >> $HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/mature_miRNA/filename.txt; grep "Assigned" $file | perl -p -e 's/\w*\s*(\d*)/$1/' >> $HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/mature_miRNA/Assigned.txt ; grep "Unassigned_Ambiguity" $file | perl -p -e 's/\w*\s*(\d*)/$1/' >> $HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/mature_miRNA/Unassigned_Ambiguity.txt; grep "Unassigned_MultiMapping" $file | perl -p -e 's/\w*\s*(\d*)/$1/' >> $HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/mature_miRNA/Unassigned_MultiMapping.txt; grep "Unassigned_NoFeatures" $file | perl -p -e 's/\w*\s*(\d*)/$1/' >> $HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/mature_miRNA/Unassigned_NoFeatures.txt; grep "Unassigned_Unmapped" $file | perl -p -e 's/\w*\s*(\d*)/$1/' >> $HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/mature_miRNA/Unassigned_Unmapped.txt; paste filename.txt Assigned.txt Unassigned_Ambiguity.txt Unassigned_MultiMapping.txt Unassigned_NoFeatures.txt Unassigned_Unmapped.txt > $HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/mature_miRNA/featureCounts.txt; done;
echo -e "Sample\tAssigned reads\tUnassigned ambiguous reads\tUnassigned multi mapping reads\tUnassigned no features reads\tUnassigned unmapped reads" | cat - $HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/mature_miRNA/featureCounts.txt > $HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/mature_miRNA/Gene_count_stats.txt
rm -f filename.txt Assigned.txt Unassigned_Ambiguity.txt Unassigned_MultiMapping.txt Unassigned_NoFeatures.txt Unassigned_Unmapped.txt featureCounts.txt

# Collect all read counts files for transfer on desktop computer
mkdir -p $HOME/scratch/miRNAseqTimeCourse/Counts/Novo-feature/mature_miRNA/ $HOME/scratch/miRNAseqTimeCourse/Counts/Novo-feature/pre_miRNA
cd $HOME/scratch/miRNAseqTimeCourse/Counts/Novo-feature/
for file in `find $HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/mature_miRNA -name *.summary`; do outfile=`basename $file | perl -p -e 's/\.summary//'`; cp $HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/mature_miRNA/$outfile/$outfile $HOME/scratch/miRNAseqTimeCourse/Counts/Novo-feature/mature_miRNA/$outfile; done;
for file in `find $HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/pre_miRNA -name *.summary`; do outfile=`basename $file | perl -p -e 's/.summary//'`; cp $HOME/scratch/miRNAseqTimeCourse/Novo-feature/count_summarisation/pre_miRNA/$outfile/$outfile $HOME/scratch/miRNAseqTimeCourse/Counts/Novo-feature/pre_miRNA/$outfile; done;


#########################################
# Compress all SAM files into BAM files #
#########################################

# Go to working directory
cd $HOME/scratch/miRNAseqTimeCourse/Novo-feature/alignment/

# Compress all SAM files into BAM files
for file in `ls $HOME/scratch/miRNAseqTimeCourse/Novo-feature/alignment/*.sam`; do sample=`basename $file | perl -p -e 's/\.sam//'`; echo "samtools view -bhS $file | samtools sort - ${sample}; rm -f $file" >> sam_to_bam.sh; done;

# Run script on Stampede
for script in `ls sam_to_bam.sh`
do
chmod 755 $script
nohup ./$script > ${script}_nohup &
done

# Perform subsequent miRNA analyses in R, follow R pipelines

