version development

import "sequencing_run.wdl" as seq_run
import "sequencing_run.define.wdl" as seq_run_def
import "sample.wdl" as s
import "patient.wdl" as p
import "runtime_collection.wdl" as rtc


workflow DefinePatient {
    input {
        String individual_id

        Array[File]+ bams
        Array[File]+ bais
        Array[File]+ target_intervals
        Array[File]? annotated_target_intervals
        Array[File]? cnv_panel_of_normals
        Array[String]? sample_names

        Array[String]? normal_sample_names

        RuntimeCollection runtime_collection
    }

    Array[String] non_optional_normal_sample_names = select_first([normal_sample_names, []])
    Boolean has_normal = length(non_optional_normal_sample_names) > 0

    # We first define SequencingRuns for each bam, and then group them by sample name into Samples.

    scatter (tuple in transpose([bams, bais, target_intervals])) {
        call seq_run_def.DefineSequencingRun {
            input:
                bam = tuple[0],
                bai = tuple[1],
                target_intervals = tuple[2],
                runtime_collection = runtime_collection
        }
        String bam_names = DefineSequencingRun.sequencing_run.name
    }
    Array[SequencingRun] seqruns_1 = DefineSequencingRun.sequencing_run
    if (defined(annotated_target_intervals)) {
        scatter (pair in zip(seqruns_1, select_first([annotated_target_intervals, []]))) {
            call seq_run.UpdateSequencingRun as UpdateAnnotatedTargetIntervals {
                input:
                    sequencing_run = pair.left,
                    annotated_target_intervals = pair.right,
            }
        }
    }
    Array[SequencingRun] seqruns_2 = select_first([UpdateAnnotatedTargetIntervals.updated_sequencing_run, seqruns_1])
    if (defined(cnv_panel_of_normals)) {
        scatter (pair in zip(seqruns_2, select_first([cnv_panel_of_normals, []]))) {
            if (size(pair.right) > 0) {
                # For some sequencing platforms a panel of normals may not be available.
                # The denoise read counts task will then just use the anntated target
                # intervals to do GC correction.
                File this_cnv_panel_of_normals = pair.right
            }
            call seq_run.UpdateSequencingRun as UpdateCnvPanelOfNormals {
                input:
                    sequencing_run = pair.left,
                    cnv_panel_of_normals = this_cnv_panel_of_normals,
            }
        }
    }
    Array[SequencingRun] seqruns_3 = select_first([UpdateCnvPanelOfNormals.updated_sequencing_run, seqruns_2])

    # GroupBy sample name:
    # We assume that sample_names and bam_names share the same uniqueness,
    # that is if the supplied sample name is the same for two input bams, then the
    # bam names should also be the same, and vice versa.

    Array[String] theses_sample_names = select_first([sample_names, bam_names])
    Array[Pair[String, Array[SequencingRun]]] sample_dict = as_pairs(collect_by_key(zip(theses_sample_names, seqruns_3)))

    # Pick tumor and normal samples apart:

    call GetTumorSampleNames {
        input:
            sample_names = theses_sample_names,
            normal_sample_names = non_optional_normal_sample_names,
            runtime_params = runtime_collection.get_tumor_sample_names
    }

    scatter (tumor_sample_name in GetTumorSampleNames.tumor_sample_names) {
        scatter (pair in sample_dict) {
            if (pair.left == tumor_sample_name) {
                Sample selected_tumor_sample = object {
                    name: pair.left,
                    bam_name: pair.right[0].name,
                    sequencing_runs: pair.right,
                    is_tumor: true,
                }
            }
        }
        Sample tumor_samples = select_all(selected_tumor_sample)[0]
    }

    if (has_normal) {
        scatter (normal_sample_name in non_optional_normal_sample_names) {
            scatter (pair in sample_dict) {
                if (pair.left == normal_sample_name) {
                    Sample selected_normal_sample = object {
                        name: pair.left,
                        bam_name: pair.right[0].name,
                        sequencing_runs: pair.right,
                        is_tumor: false,
                    }
                }
            }
            Sample this_normal_samples = select_all(selected_normal_sample)[0]
        }
        Sample best_matched_normal_sample = select_first(this_normal_samples)
    }
    Array[Sample] normal_samples = select_first([this_normal_samples, []])

    Patient pat = object {
        name: individual_id,
        samples: flatten([tumor_samples, normal_samples]),
        tumor_samples: tumor_samples,
        normal_samples: normal_samples,
        has_tumor: length(tumor_samples) > 0,
        has_normal: has_normal,
        matched_normal_sample: best_matched_normal_sample,
    }

    output {
        Patient patient = pat
    }
}

task GetTumorSampleNames {
    input {
        Array[String] sample_names
        Array[String] normal_sample_names
        Runtime runtime_params
    }

    String dollar = "$"

    command <<<
        # Convert comma-separated strings to arrays
        IFS=',' read -r -a all_names <<< "~{sep="," sample_names}"
        IFS=',' read -r -a normal_names <<< "~{sep="," normal_sample_names}"

        # Loop through all names and check if they are in the normal names list.
        # This behaves well if normal_sample_names is empty.
        for name in "~{dollar}{all_names[@]}"; do
            if [[ ! " ~{dollar}{normal_names[*]} " =~ " ~{dollar}{name} " ]]; then
                echo "$name" >> "tumor_sample_names.txt"
            fi
        done
    >>>

    output {
        Array[String] tumor_sample_names = read_lines("tumor_sample_names.txt")
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