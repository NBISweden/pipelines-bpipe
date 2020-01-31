indexBam = {

	doc "A function to index a BAM file"

	requires SAMTOOLS : "Must provide path to samtools"

    	transform("bam") to ("bam.bai") {
        	exec "$SAMTOOLS index $input.bam"
    	}
	forward input
}

flagstat = {

	requires SAMTOOLS : "Must provide path to samtools"

	exec "$SAMTOOLS flagstat $input.bam > $output"
}

samtools_filter_quality = {

	doc "Filters BAM files by quality score"

	var sample_dir : false
	var quality : "15"

	if(branch.sample_dir) { sample_dir = true }
	

	if (sample_dir) { 
		output.dir = branch.outdir + "/bam" 
	} else {
		output.dir = "bam/${branch.sample}"
	}

	requires SAMTOOLS : "Must provide path to samtools (SAMTOOLS)"

	transform("bam") to ("filtered.bam") {

		exec "$SAMTOOLS view -bq$quality -o $output $input && md5sum $output > ${output}.md5sum"

	}

}

samtools_sort_bam = {

        doc "Sort BAM files. requires samtools version 1.2 or higher"

	requires SAMTOOLS : "Must provide path to samtools (SAMTOOLS)"

        // create output_name. Will be the input where we remove extension (should be .sam) and add .bam
        String output_name = "$input" - ~/.[^.]*$/
        String output = "${output_name}.sorted.bam" 

        produce("$output") {	
		exec "$SAMTOOLS sort -o $output $input && md5sum $output > ${output}.md5sum"
	}
}


samtools_sam_to_bam = {

	doc "Convert SAM to BAM files."	

	requires SAMTOOLS : "Must provide path to samtools (SAMTOOLS)"

	// create output_name. Will be the input where we remove extension (should be .sam) and add .bam	
	String output_name = "$input" - ~/.[^.]*$/
	String output = "${output_name}.bam"

	produce("$output") {	
		exec "$SAMTOOLS view -bS -o $output $input && md5sum $output > ${output}.md5sum"
	}
}
