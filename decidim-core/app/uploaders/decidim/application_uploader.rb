# frozen_string_literal: true

module Decidim
  # This class deals with uploading files to Decidim. It is intended to just
  # hold the uploads configuration, so you should inherit from this class and
  # then tweak any configuration you need.
  class ApplicationUploader < CarrierWave::Uploader::Base
    include CarrierWave::MiniMagick

    process :validate_inside_organization

    # Override the directory where uploaded files will be stored.
    # This is a sensible default for uploaders that are meant to be mounted:
    def store_dir
      default_path = "uploads/#{model.class.to_s.underscore}/#{mounted_as}/#{model.id}"

      return File.join(Decidim.base_uploads_path, default_path) if Decidim.base_uploads_path.present?

      default_path
    end

    # When the uploaded content can't be processed, we want to make sure
    # not to expose internal tools errors to the users.
    # We'll show a generic error instead.
    def manipulate!
      super
    rescue CarrierWave::ProcessingError => e
      Rails.logger.error(e)
      raise CarrierWave::ProcessingError, I18n.t("carrierwave.errors.general")
    end

    # As of Carrierwave 2.0 fog_provider method has been deprecated, and is throwing RuntimeError
    # RuntimeError: Carrierwave fog_provider not supported: DEPRECATION WARNING: #fog_provider is deprecated...
    # We are attempting to fetch the provider from credentials, if not we consider to be file
    def provider
      fog_credentials.fetch(:provider, "file").downcase
    end

    # We overwrite the downloader to be able to fetch some elements from URL.
    def downloader
      Decidim::Downloader
    end

    protected

    # Validates that the associated model is always within an organization in
    # order to pass the organization specific settings for the file upload
    # checks (e.g. file extension, mime type, etc.).
    def validate_inside_organization
      return if model.is_a?(Decidim::Organization)
      return if model.respond_to?(:organization) && model.organization.is_a?(Decidim::Organization)

      raise CarrierWave::IntegrityError, I18n.t("carrierwave.errors.not_inside_organization")
    end

    # Checks if the file is an image based on the content type. We need this so
    # we only create different versions of the file when it's an image.
    #
    # new_file - The uploaded file.
    #
    # Returns a Boolean.
    def image?(new_file)
      content_type = model.try(:content_type) || new_file.content_type
      content_type.to_s.start_with? "image"
    end

    class << self
      # Each class inherits variants from parents and can define their own
      # variants with the set_variants class method which calss the version
      # CarrierWave macro to define versions from variants
      def variants
        @variants ||= superclass.respond_to?(:variants) ? superclass.variants.dup : {}
      end

      def set_variants
        return unless block_given?

        variants.merge!(yield)

        variants.each do |key, value|
          version key, if: :image? do
            process value
          end
        end
      end
    end
  end
end
