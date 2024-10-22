version development

## Collection of Tasks

import "runtimes.wdl" as rt


task GetSampleName {
    input {
        File bam

        Runtime runtime_params
    }

    command <<<
        set -e
        export GATK_LOCAL_JAR=~{select_first([runtime_params.jar_override, "/root/gatk.jar"])}
        gatk --java-options "-Xmx~{runtime_params.command_mem}m" \
            GetSampleName \
            -I '~{bam}' \
            -O bam_name.txt
    >>>

    output {
        String sample_name = read_string("bam_name.txt")
    }

    runtime {
        docker: runtime_params.docker
        bootDiskSizeGb: runtime_params.boot_disk_size
        memory: runtime_params.machine_mem + " MB"
        runtime_minutes: runtime_params.runtime_minutes
        disks: "local-disk " + runtime_params.disk + " HDD"
        preemptible: runtime_params.preemptible
        maxRetries: runtime_params.max_retries
        cpu: runtime_params.cpu
    }

    parameter_meta {
        bam: {localization_optional: true}
    }
}

task AnnotateIntervals {
    input {
        File interval_list

        File ref_fasta
        File ref_fasta_index
        File ref_dict

        File? mappability_track
        File? mappability_track_idx
        File? segmental_duplication_track
        File? segmental_duplication_track_idx

        Runtime runtime_params
    }

    String output_file = basename(interval_list, ".interval_list") + ".annotated.interval_list"

	command <<<
        set -e
        export GATK_LOCAL_JAR=~{select_first([runtime_params.jar_override, "/root/gatk.jar"])}
        gatk --java-options "-Xmx~{runtime_params.command_mem}m" \
            AnnotateIntervals \
            -R '~{ref_fasta}' \
            -L '~{interval_list}' \
            -O '~{output_file}' \
            --interval-merging-rule OVERLAPPING_ONLY \
            ~{"--mappability-track " + mappability_track} \
            ~{"--segmental-duplication-track " + segmental_duplication_track}
	>>>

	output {
		File annotated_interval_list = output_file
	}

    runtime {
        docker: runtime_params.docker
        bootDiskSizeGb: runtime_params.boot_disk_size
        memory: runtime_params.machine_mem + " MB"
        runtime_minutes: runtime_params.runtime_minutes
        disks: "local-disk " + runtime_params.disk + " HDD"
        preemptible: runtime_params.preemptible
        maxRetries: runtime_params.max_retries
        cpu: runtime_params.cpu
    }

    parameter_meta {
        interval_list: {localization_optional: true}
        ref_fasta: {localization_optional: true}
        ref_fasta_index: {localization_optional: true}
        ref_dict: {localization_optional: true}
        mappability_track: {localization_optional: true}
        mappability_track_idx: {localization_optional: true}
        segmental_duplication_track: {localization_optional: true}
        segmental_duplication_track_idx: {localization_optional: true}
    }
}

task PreprocessIntervals {
    input {
        File? interval_list
        File? interval_blacklist
        Array[File]? interval_lists
        File ref_fasta
        File ref_fasta_index
        File ref_dict

        Int bin_length = 0
        Int padding = 0
        String? preprocess_intervals_extra_args

        Runtime runtime_params
    }

    String preprocessed_intervals = "preprocessed.interval_list"

    command <<<
        set -e
        export GATK_LOCAL_JAR=~{select_first([runtime_params.jar_override, "/root/gatk.jar"])}
        gatk --java-options "-Xmx~{runtime_params.command_mem}m" \
            PreprocessIntervals \
            -R '~{ref_fasta}' \
            ~{"-L '" + interval_list + "'"} \
            ~{"-XL '" + interval_blacklist + "'"} \
            ~{true="-L '" false="" defined(interval_lists)}~{default="" sep="' -L '" interval_lists}~{true="'" false="" defined(interval_lists)} \
            --bin-length ~{bin_length} \
            --padding ~{padding} \
            --interval-merging-rule OVERLAPPING_ONLY \
            -O '~{preprocessed_intervals}' \
            ~{preprocess_intervals_extra_args}
    >>>

    output {
        File preprocessed_interval_list = preprocessed_intervals
    }

    runtime {
        docker: runtime_params.docker
        bootDiskSizeGb: runtime_params.boot_disk_size
        memory: runtime_params.machine_mem + " MB"
        runtime_minutes: runtime_params.runtime_minutes
        disks: "local-disk " + runtime_params.disk + " HDD"
        preemptible: runtime_params.preemptible
        maxRetries: runtime_params.max_retries
        cpu: runtime_params.cpu
    }

    parameter_meta {
        interval_list: {localization_optional: true}
        interval_lists: {localization_optional: true}
        ref_fasta: {localization_optional: true}
        ref_fasta_index: {localization_optional: true}
    }
}

task SplitIntervals {
    input {
        File? interval_list
        File ref_fasta
        File ref_fasta_index
        File ref_dict

        Int scatter_count
        String? split_intervals_extra_args

        Runtime runtime_params
    }

    String extra_args = (
        select_first([split_intervals_extra_args, ""])
        # to avoid splitting intervals:
        # + " --subdivision-mode BALANCING_WITHOUT_INTERVAL_SUBDIVISION_WITH_OVERFLOW"
        # Applied after inital scatter, so leads to more scattered intervals.
        # + " --dont-mix-contigs"
    )

    command <<<
        set -e
        export GATK_LOCAL_JAR=~{select_first([runtime_params.jar_override, "/root/gatk.jar"])}
        mkdir interval-files
        gatk --java-options "-Xmx~{runtime_params.command_mem}m" \
            SplitIntervals \
            -R '~{ref_fasta}' \
            ~{"-L '" + interval_list + "'"} \
            -scatter ~{scatter_count} \
            -O interval-files \
            ~{extra_args}
    >>>

    output {
        Array[File] interval_files = glob("interval-files/*.interval_list")
    }

    runtime {
        docker: runtime_params.docker
        bootDiskSizeGb: runtime_params.boot_disk_size
        memory: runtime_params.machine_mem + " MB"
        runtime_minutes: runtime_params.runtime_minutes
        disks: "local-disk " + runtime_params.disk + " HDD"
        preemptible: runtime_params.preemptible
        maxRetries: runtime_params.max_retries
        cpu: runtime_params.cpu
    }

    parameter_meta {
        interval_list: {localization_optional: true}
        ref_fasta: {localization_optional: true}
        ref_fasta_index: {localization_optional: true}
        ref_dict: {localization_optional: true}
    }
}

task VariantFiltration {
    input {
        File? interval_list
        File? ref_fasta
        File? ref_fasta_index
        File? ref_dict
        File vcf
        File vcf_idx

        Boolean compress_output = false

        Array[String] filter_expressions
        Array[String] filter_names
        String? variant_filtration_extra_args

        Runtime runtime_params
    }

    String output_vcf = basename(basename(vcf, ".gz"), ".vcf") + ".hard_filtered.vcf" + if compress_output then ".gz" else ""
    String output_vcf_idx = output_vcf + if compress_output then ".tbi" else ".idx"

    command <<<
        set -e
        export GATK_LOCAL_JAR=~{select_first([runtime_params.jar_override, "/root/gatk.jar"])}
        # Some variants don't have certain INFO fields, so we suppress the warning messages.
        printf "Suppressing the following warning message: 'WARN  JexlEngine - '\n" >&2
        gatk --java-options "-Xmx~{runtime_params.command_mem}m" \
            VariantFiltration \
            ~{"-R '" + ref_fasta + "'"} \
            ~{"-L '" + interval_list + "'"} \
            -V '~{vcf}' \
            ~{if (length(filter_names) > 0) then " --filter-name '" else ""}~{default="" sep="' --filter-name '" filter_names}~{if (length(filter_names) > 0) then "'" else ""} \
            ~{if (length(filter_expressions) > 0) then " --filter-expression '" else ""}~{default="" sep="' --filter-expression '" filter_expressions}~{if (length(filter_expressions) > 0) then "'" else ""} \
            --output '~{output_vcf}' \
            ~{variant_filtration_extra_args} \
            2> >(grep -v "WARN  JexlEngine - " >&2)
    >>>

    output {
        File filtered_vcf = output_vcf
        File filtered_vcf_idx = output_vcf_idx
    }

    runtime {
        docker: runtime_params.docker
        bootDiskSizeGb: runtime_params.boot_disk_size
        memory: runtime_params.machine_mem + " MB"
        runtime_minutes: runtime_params.runtime_minutes
        disks: "local-disk " + runtime_params.disk + " HDD"
        preemptible: runtime_params.preemptible
        maxRetries: runtime_params.max_retries
        cpu: runtime_params.cpu
    }

    parameter_meta {
        interval_list: {localization_optional: true}
        ref_fasta: {localization_optional: true}
        ref_fasta_index: {localization_optional: true}
        ref_dict: {localization_optional: true}
        vcf: {localization_optional: true}
        vcf_idx: {localization_optional: true}
    }
}

task LeftAlignAndTrimVariants {
    input {
        File? ref_fasta
        File? ref_fasta_index
        File? ref_dict
        File vcf
        File vcf_idx
        Int max_indel_length = 200
        Boolean dont_trim_alleles = false
        Boolean split_multi_allelics = false

        Boolean compress_output = false
        String? left_align_and_trim_variants_extra_args

        Runtime runtime_params
    }

    String output_vcf_ = basename(basename(vcf, ".gz"), ".vcf") + ".split.trimmed.vcf" + if compress_output then ".gz" else ""
    String output_vcf_idx_ = output_vcf_ + if compress_output then ".tbi" else ".idx"

    command <<<
        set -e
        export GATK_LOCAL_JAR=~{select_first([runtime_params.jar_override, "/root/gatk.jar"])}
        gatk --java-options "-Xmx~{runtime_params.command_mem}m" \
            LeftAlignAndTrimVariants \
            -R '~{ref_fasta}' \
            -V '~{vcf}' \
            --output '~{output_vcf_}' \
            --max-indel-length ~{max_indel_length} \
            ~{if (dont_trim_alleles) then " --dont-trim-alleles " else ""} \
            ~{if (split_multi_allelics) then " --split-multi-allelics " else ""} \
            ~{left_align_and_trim_variants_extra_args}
    >>>

    output {
        File output_vcf = output_vcf_
        File output_vcf_idx = output_vcf_idx_
    }

    runtime {
        docker: runtime_params.docker
        bootDiskSizeGb: runtime_params.boot_disk_size
        memory: runtime_params.machine_mem + " MB"
        runtime_minutes: runtime_params.runtime_minutes
        disks: "local-disk " + runtime_params.disk + " HDD"
        preemptible: runtime_params.preemptible
        maxRetries: runtime_params.max_retries
        cpu: runtime_params.cpu
    }

    parameter_meta {
        ref_fasta: {localization_optional: true}
        ref_fasta_index: {localization_optional: true}
        ref_dict: {localization_optional: true}
        vcf: {localization_optional: true}
        vcf_idx: {localization_optional: true}
    }
}

task SelectVariants {
    input {
        File? interval_list
        File? ref_fasta
        File? ref_fasta_index
        File? ref_dict
        File vcf
        File vcf_idx
        Boolean select_passing = false
        Boolean keep_germline = false
        Boolean compress_output = false
        String? tumor_sample_name
        String? normal_sample_name
        String? select_variants_extra_args

        Runtime runtime_params
    }

    String uncompressed_input_vcf = basename(vcf, ".gz")
    String base_name = if defined(tumor_sample_name) then sub(select_first([tumor_sample_name, ""]), " ", "+") else basename(uncompressed_input_vcf, ".vcf")
    String output_base_name = base_name + ".selected"
    
    String select_variants_output_vcf = output_base_name + ".tmp.vcf"
    String select_variants_output_vcf_idx = select_variants_output_vcf + ".idx"
    String uncompressed_selected_vcf = output_base_name + ".vcf"
    String uncompressed_selected_vcf_idx = uncompressed_selected_vcf + ".idx"
    String output_vcf = uncompressed_selected_vcf + if compress_output then ".gz" else ""
    String output_vcf_idx = output_vcf + if compress_output then ".tbi" else ".idx"

    command <<<
        set -e
        export GATK_LOCAL_JAR=~{select_first([runtime_params.jar_override, "/root/gatk.jar"])}
        gatk --java-options "-Xmx~{runtime_params.command_mem}m" \
            SelectVariants \
            ~{"-R '" + ref_fasta + "'"} \
            ~{"-L '" + interval_list + "'"} \
            -V '~{vcf}' \
            --output '~{select_variants_output_vcf}' \
            --exclude-filtered false \
            ~{"--sample-name '" + tumor_sample_name + "'"} \
            ~{"--sample-name '" + normal_sample_name + "'"} \
            ~{"-select 'vc.getGenotype(\"" + tumor_sample_name + "\").getAD().0 < vc.getGenotype(\"" + tumor_sample_name + "\").getDP()'"} \
            ~{select_variants_extra_args}

        set -uo pipefail
        # =======================================
        # We do the selection step using grep to also select germline variants.

        set +e  # grep returns 1 if no lines are found
        grep "^#" '~{select_variants_output_vcf}' > '~{uncompressed_selected_vcf}'
        num_vars=$(grep -v "^#" '~{select_variants_output_vcf}' | wc -l)

        if [ "$num_vars" -eq 0 ] || [ "~{select_passing}" == "false" ] && [ "~{keep_germline}" == "false" ] ; then
            echo ">> No variants selected."
            cp '~{select_variants_output_vcf}' '~{uncompressed_selected_vcf}'
        else
            if [ "~{select_passing}" == "true" ] ; then
                echo ">> Selecting PASSing variants ... "
                grep -v "^#" '~{select_variants_output_vcf}' | grep "PASS" >> '~{uncompressed_selected_vcf}'
                num_selected_vars=$(grep -v "^#" '~{uncompressed_selected_vcf}' | wc -l)
                echo ">> Selected $num_selected_vars PASSing out of $num_vars variants."
            fi
            if [ "~{keep_germline}" == "true" ] ; then
                echo ">> Selecting germline variants ... "
                grep -v "^#" '~{select_variants_output_vcf}' | grep "\tgermline\t" >> '~{uncompressed_selected_vcf}'
                num_selected_vars=$(grep "\tgermline\t" '~{uncompressed_selected_vcf}' | wc -l)
                echo ">> Selected $num_selected_vars germline out of $num_vars variants."
            fi
        fi

        set -e

        rm -f '~{select_variants_output_vcf}' '~{select_variants_output_vcf_idx}'

        # =======================================
        # Hack to correct a SelectVariants output bug. When selecting for samples, this
        # task only retains the first sample annotation in the header. Those annotations
        # are important for Funcotator to fill the t_alt_count and t_ref_count coverage
        # columns. This hack assumes that only one tumor sample and/or only one normal
        # sample have been selected.

        if [ "~{defined(tumor_sample_name)}" == "true" ] ; then
            echo ">> Fixing tumor sample name in vcf header ... "
            input_header=$(grep "##tumor_sample=" '~{uncompressed_selected_vcf}')
            corrected_header="##tumor_sample=~{tumor_sample_name}"
            sed -i "s/$input_header/$corrected_header/g" '~{uncompressed_selected_vcf}'
        fi
        if [ "~{defined(normal_sample_name)}" == "true" ] ; then
            echo ">> Fixing normal sample name in vcf header ... "
            input_header=$(grep "##normal_sample=" '~{uncompressed_selected_vcf}')
            corrected_header="##normal_sample=~{normal_sample_name}"
            sed -i "s/$input_header/$corrected_header/g" '~{uncompressed_selected_vcf}'
        fi

        # Selecting both PASSing and germline variants can lead to unsorted vcf.
        mv '~{uncompressed_selected_vcf}' 'unsorted.~{uncompressed_selected_vcf}'
        gatk --java-options "-Xmx~{runtime_params.command_mem}m" \
            SortVcf \
            -I 'unsorted.~{uncompressed_selected_vcf}' \
            -O '~{uncompressed_selected_vcf}' \
            ~{"-SD '" +  ref_dict + "'"}
        rm -f 'unsorted.~{uncompressed_selected_vcf}'

        set +e  # grep returns 1 if no lines are found
        grep -v "^#" '~{uncompressed_selected_vcf}' | wc -l > num_selected_vars.txt
        set -e

        if [ "~{compress_output}" == "true" ] ; then
            echo ">> Compressing selected vcf."
            bgzip -c '~{uncompressed_selected_vcf}' > '~{output_vcf}'
            gatk --java-options "-Xmx~{runtime_params.command_mem}m" \
                IndexFeatureFile \
                --input '~{output_vcf}' \
                --output '~{output_vcf_idx}'
            rm -f '~{uncompressed_selected_vcf}' '~{uncompressed_selected_vcf_idx}'
        fi
    >>>

    output {
        File selected_vcf = output_vcf
        File selected_vcf_idx = output_vcf_idx
        Int num_selected_variants = read_int("num_selected_vars.txt")
    }

    runtime {
        docker: runtime_params.docker
        bootDiskSizeGb: runtime_params.boot_disk_size
        memory: runtime_params.machine_mem + " MB"
        runtime_minutes: runtime_params.runtime_minutes
        disks: "local-disk " + runtime_params.disk + " HDD"
        preemptible: runtime_params.preemptible
        maxRetries: runtime_params.max_retries
        cpu: runtime_params.cpu
    }

    parameter_meta {
        interval_list: {localization_optional: true}
        ref_fasta: {localization_optional: true}
        ref_fasta_index: {localization_optional: true}
        # ref_dict: {localization_optional: true}  # needs to be localized for SortVcf
        vcf: {localization_optional: true}
        vcf_idx: {localization_optional: true}
    }
}

task MergeVCFs {
    # Consider replacing MergeVcfs with GatherVcfsCloud once the latter is out of beta.

	input {
        File? ref_fasta
        File? ref_fasta_index
        File? ref_dict
        Array[File] vcfs
        Array[File] vcfs_idx
        String output_name
        Boolean compress_output = false

        Runtime runtime_params
    }

    Int diskGB = runtime_params.disk + ceil(1.5 * size(vcfs, "GB"))

    String output_vcf = output_name + ".vcf" + if compress_output then ".gz" else ""
    String output_vcf_idx = output_vcf + if compress_output then ".tbi" else ".idx"

    command <<<
        set -e
        export GATK_LOCAL_JAR=~{select_first([runtime_params.jar_override, "/root/gatk.jar"])}
        gatk --java-options "-Xmx~{runtime_params.command_mem}m" \
            MergeVcfs \
            ~{sep="' " prefix("-I '", vcfs)}' \
            ~{"-R '" + ref_fasta + "'"} \
            ~{"-D '" + ref_dict + "'"} \
            -O '~{output_vcf}'
    >>>

    output {
    	File merged_vcf = output_vcf
        File merged_vcf_idx = output_vcf_idx
    }

    runtime {
        docker: runtime_params.docker
        bootDiskSizeGb: runtime_params.boot_disk_size
        memory: runtime_params.machine_mem + " MB"
        runtime_minutes: runtime_params.runtime_minutes
        disks: "local-disk " + diskGB + " HDD"
        preemptible: runtime_params.preemptible
        maxRetries: runtime_params.max_retries
        cpu: runtime_params.cpu
    }

    # Optional localization leads to cromwell error.
    # parameter_meta {
    #     vcfs: {localization_optional: true}
    #     vcfs_idx: {localization_optional: true}
    # }
}

task MergeMAFs {
    # This tasks weakly assumes that all mafs have the same header
    # and stronly assumes the same column order.

	input {
        Array[File] mafs  # assumes uncompressed
        String output_name
        Boolean compress_output = false

        Runtime runtime_params
    }

    String uncompressed_output_maf = output_name + ".maf"
    String output_maf = output_name + ".maf" + if compress_output then ".gz" else ""
    String dollar = "$"

    command <<<
        set -euxo pipefail

        # Convert WDL array to a temporary file
        printf "~{sep='\n' mafs}" > temp_mafs.txt

        # Read temporary file into a shell array
        mapfile -t maf_files < temp_mafs.txt

        # Extract leading comment lines from first file
        grep "^#" "~{dollar}{maf_files[0]}" > '~{uncompressed_output_maf}'

        # Extract column headers from first file
        # (|| true is necessary since either grep or head return non-zero exit code; don't understand why.)
        grep -v "^#" "~{dollar}{maf_files[0]}" | head -n 1 >> '~{uncompressed_output_maf}' || true

        # Extract variants
        for maf in "~{dollar}{maf_files[@]}" ; do
            grep -v "^#" "$maf" | tail -n +2 >> '~{uncompressed_output_maf}' || true
        done

        if [ "~{compress_output}" == "true" ] ; then
            echo ">> Compressing merged MAF."
            gzip -c '~{uncompressed_output_maf}' > '~{output_maf}'
            rm -f '~{uncompressed_output_maf}'
        fi
        # else: uncompressed_output_maf == output_maf by design

        rm -f temp_mafs.txt
    >>>

    output {
    	File merged_maf = output_maf
    }

    runtime {
        docker: runtime_params.docker
        bootDiskSizeGb: runtime_params.boot_disk_size
        memory: runtime_params.machine_mem + " MB"
        runtime_minutes: runtime_params.runtime_minutes
        disks: "local-disk " + runtime_params.disk + " HDD"
        preemptible: runtime_params.preemptible
        maxRetries: runtime_params.max_retries
        cpu: runtime_params.cpu
    }
}

task MergeBams {
    input {
        File ref_fasta
        File ref_fasta_index
        File ref_dict
        Array[File]+ bams
        Array[File]+ bais
        String merged_bam_name

        Runtime runtime_params
    }

    Int disk_spaceGB = 4 * ceil(size(bams, "GB")) + runtime_params.disk
    String output_bam_name = merged_bam_name + ".bam"
    String output_bai_name = merged_bam_name + ".bai"

    command <<<
        set -e
        export GATK_LOCAL_JAR=~{select_first([runtime_params.jar_override, "/root/gatk.jar"])}
        gatk --java-options "-Xmx~{runtime_params.command_mem}m" \
            GatherBamFiles \
            ~{sep="' " prefix("-I '", bams)}' \
            -O unsorted.out.bam \
            -R '~{ref_fasta}'

        # We must sort because adjacent scatters may have overlapping (padded) assembly
        # regions, hence overlapping bamouts

        gatk --java-options "-Xmx~{runtime_params.command_mem}m" \
            SortSam \
            -I unsorted.out.bam \
            -O '~{output_bam_name}' \
            --SORT_ORDER coordinate \
            --VALIDATION_STRINGENCY LENIENT

        gatk --java-options "-Xmx~{runtime_params.command_mem}m" \
            BuildBamIndex \
            -I '~{output_bam_name}' \
            --VALIDATION_STRINGENCY LENIENT
    >>>

    output {
        File merged_bam = output_bam_name
        File merged_bai = output_bai_name
    }

    runtime {
        docker: runtime_params.docker
        bootDiskSizeGb: runtime_params.boot_disk_size
        memory: runtime_params.machine_mem + " MB"
        runtime_minutes: runtime_params.runtime_minutes
        disks: "local-disk " + disk_spaceGB + " HDD"
        preemptible: runtime_params.preemptible
        maxRetries: runtime_params.max_retries
        cpu: runtime_params.cpu
    }

    parameter_meta {
        ref_fasta: {localization_optional: true}
        ref_fasta_index: {localization_optional: true}
        ref_dict: {localization_optional: true}
        # bams: {localization_optional: true}  # samtools requires localization
    }
}