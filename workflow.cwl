cwlVersion: v1.0
class: Workflow

requirements:
    - class: ScatterFeatureRequirement
    - class: StepInputExpressionRequirement
    - class: InlineJavascriptRequirement

inputs:
    genome:
        type: File
        secondaryFiles:
            - .amb
            - .ann
            - .bwt
            - .pac
            - .sa
            - .fai
            - ^.dict
    bwa_in1_fastq:
      type: 
          type: array
          items: File
    bwa_in2_fastq:
      type:
          type: array
          items: File
    bwa_out_sam_filename: string[]
    bwa_readgroup: string[]
    bwa_c: int
    bwa_M: boolean
    sambamba_output_format:
        type:
            type: enum
            symbols: [sam, bam, cram, json]
    sambamba_sam-input: boolean
    markdup_out_bam_filename: string
    
    gatk_jar: File
    haplotype_caller_vcf_out: string
    
    select_variants_types:
        type:
          type: array
          items:
            type: array
            items: string
    select_variants_out: string[]
     
    variant_filtration_names:
        type:
           type: array
           items:
             type: array
             items: string
    variant_filtration_exp: 
        type:
           type: array
           items:
             type: array
             items: string
    variant_filtration_out: string[]
    combine_variants_out: string
    assume_identical_samples: boolean
    
outputs:
    view_flagstat:
        type: File[]
        outputSource: sambamba_view_flagstat/output_flagstat
    sort_flagstat:
        type: File[]
        outputSource: sambamba_sort_flagstat/output_flagstat
    markdup_flagstat:
        type: File
        outputSource: sambamba_markdup_flagstat/output_flagstat
    markdup_bam_output:
        type: File
        outputSource: sambamba_markdup/output_bam
    interval_output:
        type: File
        outputSource: gatk_realigner_target_creator/output_intervals
    indelrealigner_bam_output:
        type: File
        outputSource: gatk_indel_realigner/output_bam
    haplotype_caller_vcf:
        type: File
        outputSource: gatk_haplotype_caller/output_vcf
    select_variants_vcf:
        type: File[]
        outputSource: gatk_select_variants/output_vcf
    variant_filtration_vcf:
        type: File[]
        outputSource: gatk_variant_filtration/output_vcf
    combine_variants_vcf:
        type: File
        outputSource: gatk_combine_variants/output_vcf

steps:
    bwa_mem:
        run: ../CWL-CommandLineTools/BWA/0.7.5a/mem.cwl
        in:
            idxbase: genome
            in1_fastq: bwa_in1_fastq
            in2_fastq: bwa_in2_fastq
            out_sam_filename: bwa_out_sam_filename
            read_group: bwa_readgroup
            c: bwa_c
            M: bwa_M
        scatter: [in1_fastq, in2_fastq, out_sam_filename, read_group]
        scatterMethod: dotproduct
        out: [output_sam]

    sambamba_view:
        run: ../CWL-CommandLineTools/Sambamba/0.6.7/view.cwl
        in:
            input: bwa_mem/output_sam
            output_format: sambamba_output_format
            sam-input: sambamba_sam-input
        scatter: [input]
        out: [output]
    
    sambamba_view_flagstat:
        run: ../CWL-CommandLineTools/Sambamba/0.6.7/flagstat.cwl
        in:
            input: sambamba_view/output
        scatter: [input]
        out: [output_flagstat]
        
    sambamba_sort:
        run: ../CWL-CommandLineTools/Sambamba/0.6.7/sort.cwl
        in:
            input: sambamba_view/output    
        scatter: [input]
        out: [output_bam]

    sambamba_sort_flagstat:
        run: ../CWL-CommandLineTools/Sambamba/0.6.7/flagstat.cwl
        in:
            input: sambamba_sort/output_bam
        scatter: [input]
        out: [output_flagstat]
    
    sambamba_markdup:
        run: ../CWL-CommandLineTools/Sambamba/0.6.7/markdup.cwl
        in:
            out_bam_filename: markdup_out_bam_filename
            input: sambamba_sort/output_bam
        out: [output_bam]
    
    sambamba_markdup_flagstat:
        run: ../CWL-CommandLineTools/Sambamba/0.6.7/flagstat.cwl
        in:
            input: sambamba_markdup/output_bam
        out: [output_flagstat]
    
    gatk_realigner_target_creator:
        run: ../CWL-CommandLineTools/GATK/3.4-46/RealignerTargetCreator.cwl
        in:
            gatk_jar: gatk_jar
            reference_sequence: genome
            input: sambamba_markdup/output_bam
        out: [output_intervals]
    
    gatk_indel_realigner:
        run: ../CWL-CommandLineTools/GATK/3.4-46/IndelRealigner.cwl
        in:
            gatk_jar: gatk_jar
            reference_sequence: genome
            input: sambamba_markdup/output_bam
            targetIntervals: gatk_realigner_target_creator/output_intervals
        out: [output_bam]
        
    gatk_haplotype_caller:
        run: ../CWL-CommandLineTools/GATK/3.4-46/HaplotypeCaller.cwl
        in:
            gatk_jar: gatk_jar
            reference_sequence: genome
            input: 
                source: gatk_indel_realigner/output_bam
                valueFrom: ${ return [ self ]; }
            out: haplotype_caller_vcf_out
        out: [output_vcf]
    
    gatk_select_variants:
        run: ../CWL-CommandLineTools/GATK/3.4-46/SelectVariants.cwl
        in:
            gatk_jar: gatk_jar
            reference_sequence: genome
            variant: gatk_haplotype_caller/output_vcf
            out: select_variants_out
            selectType: select_variants_types
        scatter: [selectType, out]
        scatterMethod: dotproduct
        out: [output_vcf]
    
    gatk_variant_filtration:
        run: ../CWL-CommandLineTools/GATK/3.4-46/VariantFiltration.cwl
        in:
            gatk_jar: gatk_jar
            reference_sequence: genome
            variant: gatk_select_variants/output_vcf
            out: variant_filtration_out
            filterName: variant_filtration_names
            filterExpression: variant_filtration_exp
        scatter: [variant, out, filterName, filterExpression]   
        scatterMethod: dotproduct
        out: [output_vcf]  
    
    gatk_combine_variants:
        run: ../CWL-CommandLineTools/GATK/3.4-46/CombineVariants.cwl
        in:
            gatk_jar: gatk_jar
            reference_sequence: genome
            variant: gatk_variant_filtration/output_vcf
            out: combine_variants_out
            assumeIdenticalSamples: assume_identical_samples
        out: [output_vcf]