# coding: utf-8
require 'spree/core/validators/email'
require 'prawn'

module Spree
  class GiftCard < ActiveRecord::Base

    include ActionView::Helpers::NumberHelper

    UNACTIVATABLE_ORDER_STATES = ["complete", "awaiting_return", "returned"]

    attr_accessible :email, :name, :note, :variant_id

    belongs_to :variant
    belongs_to :line_item

    has_many :transactions, class_name: 'Spree::GiftCardTransaction'

    validates :code,               presence: true, uniqueness: true
    validates :current_value,      presence: true
    validates :original_value,     presence: true

    before_validation :generate_code, on: :create
    before_validation :set_calculator, on: :create
    before_validation :set_values, on: :create

    calculated_adjustments

    def apply(order)
      # Nothing to do if the gift card is already associated with the order
      return if order.gift_credit_exists?(self)
      order.update!
      create_adjustment(I18n.t(:gift_card), order, order, true)
      order.update!
    end

    # Calculate the amount to be used when creating an adjustment
    def compute_amount(calculable)
      self.calculator.compute(calculable, self)
    end

    def debit(amount, order)
      raise 'Cannot debit gift card by amount greater than current value.' if (self.current_value - amount.to_f.abs) < 0
      transaction = self.transactions.build
      transaction.amount = amount
      transaction.order  = order
      self.current_value = self.current_value - amount.abs
      self.save
    end

    def price
      self.line_item ? self.line_item.price * self.line_item.quantity : self.variant.price
    end

    def order_activatable?(order)
      order &&
      created_at < order.created_at &&
      current_value > 0 &&
      !UNACTIVATABLE_ORDER_STATES.include?(order.state)
    end

    def attachment
      tmp_file = Tempfile.new(['Gutschwein', '.pdf'])
      Prawn::Document.generate(tmp_file,
                                :page_size => 'A4',
                                :page_layout => :landscape,
                                :margin => 0,
                                :info => {
                                  :Title => "Gutschein Code #{code}",
                                  :Author => "MeinekleineFarm.org UG (haftungsbeschränkt)",
                                  :Subject => "Ihr Gutschein von MeinekleineFarm.org",
                                  :Keywords => "Gutschein, MeineKleineFarm.org, PDF",
                                  :Creator => "Ruby #{RUBY_VERSION}",
                                  :CreationDate => Time.now
                                }
                              ) do |pdf|
        pdf.font_families.update("Yanone Kaffeesatz" => {
          :thin => Rails.root.join('app', 'assets', 'fonts', 'YanoneKaffeesatz-Thin.ttf').to_s,
          :light => Rails.root.join('app', 'assets', 'fonts', 'YanoneKaffeesatz-Light.ttf').to_s,
          :normal => Rails.root.join('app', 'assets', 'fonts', 'YanoneKaffeesatz-Regular.ttf').to_s,
          :bold => Rails.root.join('app', 'assets', 'fonts', 'YanoneKaffeesatz-Bold.ttf').to_s
        })

        pdf.fill_color '362213'
        #pdf.fill_color 'ffffff'
        pdf.font "Yanone Kaffeesatz", :size => 22, :style => :normal
        pdf.font_size 22

#        raise Prawn::Document::PageGeometry::SIZES["A5"].inspect
        pdf.image Rails.root.join('app', 'assets', 'images', 'flyer_background.jpg'),
                :at  => [Prawn::Document::PageGeometry::SIZES["A5"][0], Prawn::Document::PageGeometry::SIZES["A5"][1]],
                :fit => Prawn::Document::PageGeometry::SIZES["A5"]

        pdf.bounding_box [Prawn::Document::PageGeometry::SIZES["A5"][0] + 42, 183], :width => 110, :height => 91 do
#          pdf.stroke_color 'FF0000'
#          pdf.stroke_bounds
          pdf.font "Yanone Kaffeesatz", :size => 136, :style => :bold do
            pdf.text number_to_currency(15, :precision => 0 ),
              :rotate => 8,
              :rotate_around => :center,
              :overflow => :shrink_to_fit,
              :character_spacing => -7.0,
              :kerning => false,
              :align => :center,
              :valign => :center
          end
        end

        pdf.bounding_box [Prawn::Document::PageGeometry::SIZES["A5"][0] + 170, 174], :width => 200, :height => 56 do
#          pdf.stroke_color 'FF0000'
#          pdf.stroke_bounds
          pdf.font "Helvetica", :size => 24, :style => :bold do
            pdf.text "Code: #{code}",
              :rotate => 5,
              :rotate_around => :center,
              :overflow => :shrink_to_fit,
              :kerning => true,
              :align => :center,
              :valign => :center
          end
        end

      end
    end

    private

    def generate_code
      until self.code.present? && self.class.where(code: self.code).count == 0
        self.code = Digest::SHA1.hexdigest([Time.now, rand].join)[0...8]
      end
    end

    def set_calculator
      self.calculator = Spree::Calculator::GiftCard.new
    end

    def set_values
      self.current_value  = self.variant.try(:price)
      self.original_value = self.variant.try(:price)
    end


  end
end
