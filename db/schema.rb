# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_30_213000) do
  create_table "autorias", force: :cascade do |t|
    t.integer "parlamentar_id", null: false
    t.integer "proposta_id", null: false
    t.string "tipo_autoria", default: "Autor"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["parlamentar_id", "proposta_id"], name: "index_autorias_on_parlamentar_id_and_proposta_id", unique: true
    t.index ["parlamentar_id"], name: "index_autorias_on_parlamentar_id"
    t.index ["proposta_id"], name: "index_autorias_on_proposta_id"
  end

  create_table "despesas", force: :cascade do |t|
    t.integer "parlamentar_id", null: false
    t.string "external_doc_id", null: false
    t.integer "ano", null: false
    t.integer "mes", null: false
    t.string "tipo_despesa", null: false
    t.string "fornecedor"
    t.string "cnpj_cpf_fornecedor"
    t.decimal "valor_liquido", precision: 12, scale: 2, default: "0.0", null: false
    t.date "data_documento"
    t.string "numero_documento"
    t.string "url_documento"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["data_documento"], name: "index_despesas_on_data_documento"
    t.index ["parlamentar_id", "ano", "mes"], name: "index_despesas_on_parlamentar_id_and_ano_and_mes"
    t.index ["parlamentar_id", "external_doc_id"], name: "index_despesas_on_parlamentar_id_and_external_doc_id", unique: true
    t.index ["parlamentar_id"], name: "index_despesas_on_parlamentar_id"
  end

  create_table "parlamentares", force: :cascade do |t|
    t.string "external_id", null: false
    t.string "casa", null: false
    t.string "nome", null: false
    t.string "nome_civil"
    t.string "partido"
    t.string "uf"
    t.string "foto_url"
    t.string "email"
    t.string "telefone"
    t.string "gabinete_predio"
    t.string "gabinete_andar"
    t.string "gabinete_sala"
    t.string "situacao"
    t.string "escolaridade"
    t.date "data_nascimento"
    t.string "municipio_nascimento"
    t.string "uf_nascimento"
    t.string "url_website"
    t.json "redes_sociais", default: []
    t.datetime "dados_sincronizados_em"
    t.datetime "propostas_sincronizadas_em"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "propostas_count", default: 0, null: false
    t.decimal "total_despesas", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "despesas_sincronizadas_em"
    t.integer "votos_count", default: 0, null: false
    t.datetime "votos_sincronizados_em"
    t.index ["casa", "external_id"], name: "index_parlamentares_on_casa_and_external_id", unique: true
    t.index ["casa"], name: "index_parlamentares_on_casa"
    t.index ["nome"], name: "index_parlamentares_on_nome"
    t.index ["partido"], name: "index_parlamentares_on_partido"
    t.index ["propostas_count"], name: "index_parlamentares_on_propostas_count"
    t.index ["uf"], name: "index_parlamentares_on_uf"
  end

  create_table "propostas", force: :cascade do |t|
    t.string "external_id", null: false
    t.string "casa", null: false
    t.string "sigla_tipo", null: false
    t.string "descricao_tipo"
    t.string "numero"
    t.integer "ano"
    t.text "ementa"
    t.text "ementa_detalhada"
    t.text "keywords"
    t.date "data_apresentacao"
    t.string "status_situacao"
    t.string "status_orgao"
    t.text "status_despacho"
    t.string "status_regime"
    t.string "url_inteiro_teor"
    t.string "uri_api"
    t.datetime "detalhes_sincronizados_em"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ano"], name: "index_propostas_on_ano"
    t.index ["casa", "external_id"], name: "index_propostas_on_casa_and_external_id", unique: true
    t.index ["casa"], name: "index_propostas_on_casa"
    t.index ["data_apresentacao"], name: "index_propostas_on_data_apresentacao"
    t.index ["sigla_tipo"], name: "index_propostas_on_sigla_tipo"
  end

  create_table "votacoes", force: :cascade do |t|
    t.string "external_id", null: false
    t.string "casa", null: false
    t.integer "proposta_id"
    t.string "proposta_identificacao"
    t.string "orgao"
    t.datetime "data"
    t.text "descricao"
    t.text "resumo_efeito"
    t.integer "aprovacao"
    t.integer "votos_sim", default: 0, null: false
    t.integer "votos_nao", default: 0, null: false
    t.integer "votos_outros", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["casa", "external_id"], name: "index_votacoes_on_casa_and_external_id", unique: true
    t.index ["data"], name: "index_votacoes_on_data"
    t.index ["proposta_id"], name: "index_votacoes_on_proposta_id"
  end

  create_table "votos_parlamentares", force: :cascade do |t|
    t.integer "votacao_id", null: false
    t.integer "parlamentar_id", null: false
    t.string "tipo_voto", null: false
    t.string "partido_na_votacao"
    t.string "uf_na_votacao"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["parlamentar_id", "tipo_voto"], name: "index_votos_parlamentares_on_parlamentar_id_and_tipo_voto"
    t.index ["parlamentar_id"], name: "index_votos_parlamentares_on_parlamentar_id"
    t.index ["votacao_id", "parlamentar_id"], name: "index_votos_parlamentares_on_votacao_id_and_parlamentar_id", unique: true
    t.index ["votacao_id"], name: "index_votos_parlamentares_on_votacao_id"
  end

  add_foreign_key "autorias", "parlamentares"
  add_foreign_key "autorias", "propostas"
  add_foreign_key "despesas", "parlamentares"
  add_foreign_key "votacoes", "propostas"
  add_foreign_key "votos_parlamentares", "parlamentares"
  add_foreign_key "votos_parlamentares", "votacoes"
end
