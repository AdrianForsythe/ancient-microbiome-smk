checkpoint Extract_TaxIDs:
    """Create taxid directory

    For a sample, create taxid for each entry in krakenuniq output
    taxID.pathogens. Downstream rules use the taxid directories as
    input, but it is not known beforehand which these are; they are
    determined by the finds in krakenuniq.

    """
    input:
        pathogens="results/KRAKENUNIQ/{sample}/taxID.pathogens",
    output:
        dir=directory("results/AUTHENTICATION/{sample}"),
    log:
        "logs/EXTRACT_TAXIDS/{sample}.log",
    shell:
        "mkdir -p {output.dir}; "
        "while read taxid; do mkdir {output.dir}/$taxid; done<{input.pathogens}"


rule aggregate:
    """aggregate rule: generate all sample/taxid/refid combinations to
    generate targets.

    Problem: refid depends on rule MaltExtract having been run, so
    that should presumably be triggered before this step. Therefore
    maltextract should also be a checkpoint?

    """
    input:
        aggregate_dir,
        aggregate_PMD,
        aggregate_plots,
        aggregate_post,
    output:
        "results/AUTHENTICATION/.{sample}_done",
    log:
        "logs/AGGREGATE/{sample}.log",
    shell:
        "touch {output}; "


rule Make_Node_List:
    """Generate a list of species names for a taxonomic identifier"""
    input:
        dir="results/AUTHENTICATION/{sample}/{taxid}/",
    output:
        node_list="results/AUTHENTICATION/{sample}/{taxid}/node_list.txt",
    params:
        tax_db=config["krakenuniq_db"],
    log:
        "logs/MAKE_NODE_LIST/{sample}_{taxid}.log",
    shell:
        "awk -v var={wildcards.taxid} '{{ if($1==var) print $0 }}' {params.tax_db}/taxDB | cut -f3 > {output.node_list}"


checkpoint Malt_Extract:
    """Convert rma6 output to misc usable formats"""
    input:
        rma6="results/MALT/{sample}.trimmed.rma6",
        node_list="results/AUTHENTICATION/{sample}/{taxid}/node_list.txt",
    output:
        extract=directory(
            "results/AUTHENTICATION/{sample}/{taxid}/{sample}.trimmed.rma6_MaltExtract_output"
        ),
    params:
        ncbi_db=config["ncbi_db"],
    threads: 4
    log:
        "logs/MALT_EXTRACT/{sample}_{taxid}.log",
    conda:
        "../envs/malt.yaml"
    envmodules:
        *config["envmodules"]["malt"],
    message:
        "RUNNING MALT EXTRACT FOR SAMPLE {input.rma6}"
    shell:
        "time MaltExtract -i {input.rma6} -f def_anc -o {output.extract} --reads --threads {threads} --matches --minPI 85.0 --maxReadLength 0 --minComp 0.0 --meganSummary -r {params.ncbi_db} -t {input.node_list} -v 2> {log}"


rule Post_Processing:
    input:
        extract="results/AUTHENTICATION/{sample}/{taxid}/{sample}.trimmed.rma6_MaltExtract_output",
        node_list="results/AUTHENTICATION/{sample}/{taxid}/node_list.txt",
    output:
        analysis="results/AUTHENTICATION/{sample}/{taxid}/{sample}.trimmed.rma6_MaltExtract_output/analysis.RData",
    threads: 4
    log:
        "logs/POST_PROCESSING/{sample}_{taxid}.log",
    conda:
        "../envs/malt.yaml"
    envmodules:
        *config["envmodules"]["malt"],
    shell:
        "postprocessing.AMPS.r -m def_anc -r {input.extract} -t {threads} -n {input.node_list} 2> {log}"


rule Breadth_Of_Coverage:
    input:
        extract="results/AUTHENTICATION/{sample}/{taxid}/{sample}.trimmed.rma6_MaltExtract_output",
        sam="results/MALT/{sample}.trimmed.sam.gz",
    output:
        name_list="results/AUTHENTICATION/{sample}/{taxid}/{refid}/name.list",
        sam="results/AUTHENTICATION/{sample}/{taxid}/{refid}/{taxid}.sam",
        bam="results/AUTHENTICATION/{sample}/{taxid}/{refid}/{taxid}.bam",
        sorted_bam="results/AUTHENTICATION/{sample}/{taxid}/{refid}/{taxid}.sorted.bam",
        breadth_of_coverage="results/AUTHENTICATION/{sample}/{taxid}/{refid}/{taxid}.breadth_of_coverage",
        fasta="results/AUTHENTICATION/{sample}/{taxid}/{refid}/{taxid}.fasta",
    params:
        malt_fasta=config["malt_nt_fasta"],
        ref_id=get_ref_id,
    message:
        "COMPUTING BREADTH OF COVERAGE, EXTRACTING REFERENCE SEQUENCE FOR VISUALIZING ALIGNMENTS WITH IGV"
    log:
        "logs/BREADTH_OF_COVERAGE/{sample}_{taxid}_{refid}.log",
    conda:
        "../envs/malt.yaml"
    envmodules:
        *config["envmodules"]["malt"],
    shell:
        "echo {params.ref_id} > {output.name_list}; "
        "zgrep {params.ref_id} {input.sam} | uniq > {output.sam}; "
        "samtools view -bS {output.sam} > {output.bam}; "
        "samtools sort {output.bam} > {output.sorted_bam}; "
        "samtools index {output.sorted_bam}; "
        "samtools depth -a {output.sorted_bam} > {output.breadth_of_coverage}; "
        "seqtk subseq {params.malt_fasta} {output.name_list} > {output.fasta}"


rule Read_Length_Distribution:
    input:
        #nodeentries="results/AUTHENTICATION/{sample}/{taxid}/{sample}.trimmed.rma6_MaltExtract_output/default/readDist/{sample}.trimmed.rma6_additionalNodeEntries.txt",
        bam="results/AUTHENTICATION/{sample}/{taxid}/{refid}/{taxid}.sorted.bam",
    output:
        distribution="results/AUTHENTICATION/{sample}/{taxid}/{refid}/{taxid}.read_length.txt",
    message:
        "COMPUTING READ LENGTH DISTRIBUTION"
    log:
        "logs/READ_LENGTH_DISTRIBUTION/{sample}_{taxid}_{refid}.log",
    conda:
        "../envs/malt.yaml"
    envmodules:
        *config["envmodules"]["malt"],
    shell:
        "samtools view {input.bam} | awk '{{ print length($10) }}' > {output.distribution}"


rule PMD_scores:
    input:
        #nodeentries="results/AUTHENTICATION/{sample}/{taxid}/{sample}.trimmed.rma6_MaltExtract_output/default/readDist/{sample}.trimmed.rma6_additionalNodeEntries.txt",
        bam="results/AUTHENTICATION/{sample}/{taxid}/{refid}/{taxid}.sorted.bam",
    output:
        scores="results/AUTHENTICATION/{sample}/{taxid}/{refid}/{taxid}.PMDscores.txt",
    message:
        "COMPUTING PMD SCORES"
    log:
        "logs/PMD_SCORES/{sample}_{taxid}_{refid}.log",
    conda:
        "../envs/malt.yaml"
    envmodules:
        *config["envmodules"]["malt"],
    shell:
        "samtools view -h {input.bam} | pmdtools --printDS > {output.scores}"


rule Authentication_Plots:
    input:
        dir="results/AUTHENTICATION/{sample}/{taxid}",
        #nodeentries="results/AUTHENTICATION/{sample}/{taxid}/{sample}.trimmed.rma6_MaltExtract_output/default/readDist/{sample}.trimmed.rma6_additionalNodeEntries.txt",
        node_list="results/AUTHENTICATION/{sample}/{taxid}/node_list.txt",
        distribution="results/AUTHENTICATION/{sample}/{taxid}/{refid}/{taxid}.read_length.txt",
        scores="results/AUTHENTICATION/{sample}/{taxid}/{refid}/{taxid}.PMDscores.txt",
        breadth_of_coverage="results/AUTHENTICATION/{sample}/{taxid}/{refid}/{taxid}.breadth_of_coverage",
    output:
        plot="results/AUTHENTICATION/{sample}/{taxid}/{refid}/authentic_Sample_{sample}.trimmed.rma6_TaxID_{taxid}.pdf",
    params:
        exe=WORKFLOW_DIR / "scripts/authentic.R",
    message:
        "MAKING AUTHENTICATION AND VALIDATION PLOTS"
    log:
        "logs/AUTHENTICATION_PLOTS/{sample}_{taxid}_{refid}.log",
    conda:
        "../envs/malt.yaml"
    envmodules:
        *config["envmodules"]["malt"],
    shell:
        "Rscript {params.exe} {wildcards.taxid} {wildcards.sample}.trimmed.rma6 {input.dir}/{wildcards.refid}"


rule Deamination:
    input:
        bam="results/AUTHENTICATION/{sample}/{taxid}/{refid}/{taxid}.sorted.bam",
    output:
        tmp="results/AUTHENTICATION/{sample}/{taxid}/{refid}/PMD_temp.txt",
        pmd="results/AUTHENTICATION/{sample}/{taxid}/{refid}/PMD_plot.frag.pdf",
    message:
        "INFERRING DEAMINATION PATTERN FROM CPG SITES"
    log:
        "logs/DEAMINATION/{sample}_{taxid}_{refid}.log",
    conda:
        "../envs/malt.yaml"
    envmodules:
        *config["envmodules"]["malt"],
    shell:
        "samtools view {input.bam} | pmdtools --platypus > {output.tmp}; "
        "cd results/AUTHENTICATION/{wildcards.sample}/{wildcards.taxid}/{wildcards.refid}; "
        "R CMD BATCH $(which plotPMD); "
