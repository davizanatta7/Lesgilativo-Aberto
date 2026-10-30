class CreateDespesas < ActiveRecord::Migration[8.1]
  def change
    create_table :despesas do |t|
      t.references :parlamentar, null: false, foreign_key: true
      t.string :external_doc_id, null: false
      t.integer :ano, null: false
      t.integer :mes, null: false
      t.string :tipo_despesa, null: false
      t.string :fornecedor
      t.string :cnpj_cpf_fornecedor
      t.decimal :valor_liquido, precision: 12, scale: 2, default: 0.0, null: false
      t.date :data_documento
      t.string :numero_documento
      t.string :url_documento

      t.timestamps
    end

    add_index :despesas, [ :parlamentar_id, :external_doc_id ], unique: true
    add_index :despesas, [ :parlamentar_id, :ano, :mes ]
    add_index :despesas, :data_documento

    add_column :parlamentares, :total_despesas, :decimal, precision: 12, scale: 2, default: 0.0, null: false
    add_column :parlamentares, :despesas_sincronizadas_em, :datetime
  end
end

