require 'mini_magick'

def extract_energy_profile(image)
  width = image.width
  height = image.height
  energy_profile = []
  sample_region_start = (height * 0.2).to_i
  sample_region_end = (height * 0.8).to_i

  all_pixels = image.get_pixels
  step = (width / 100.0).ceil
  step = 1 if step < 1

  (0...width).step(step).each do |x|
    total_intensity = 0
    sample_count = 0

    (sample_region_start..sample_region_end).each do |y|
      pixel = all_pixels[y][x]
      intensity = pixel ? pixel[0] : 255
      total_intensity += (255 - intensity)
      sample_count += 1
    end

    energy_profile << (total_intensity / sample_count.to_f)
  end

  energy_profile
end

begin
  path = '/var/home/b08x/Workspace/prosodic-text-converter/spectrograms/test_spectrogram.png'
  image = MiniMagick::Image.open(path)

  profile = extract_energy_profile(image)
  puts "Extracted profile with #{profile.length} points"
  puts "Min energy: #{profile.min.round(2)}"
  puts "Max energy: #{profile.max.round(2)}"
  puts "Avg energy: #{(profile.sum / profile.length).round(2)}"

  # Check for variation
  if profile.min != profile.max
    puts 'SUCCESS: Energy profile is varied!'
  else
    puts 'FAILURE: Energy profile is flat.'
  end
rescue StandardError => e
  puts "Error: #{e.message}"
  puts e.backtrace
end
