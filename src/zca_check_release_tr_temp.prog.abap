************************************************************************
* Project     : Erajaya Columbus                                       *
* RICEF Name  : -                                                      *
* Program Name: ZCA_CHECK_RELEASE_TR_TEMP                              *
* Description : Check And Release TR (OO Version)                      *
* Create By   : GNAPIS                                                 *
* Create Date : 23.10.2026                                            *
* TR No.      :                                                        *
*----------------------------------------------------------------------
* Modification History                                                 *
*----------------------------------------------------------------------
* Change ID.  Name        Date       Request No.    Defect/CR No.      *
* Description:                                                         *
*----------------------------------------------------------------------
* CH001      GNAPIS      23-OCT-26  ERDKxxxxxx    IS:NNNNNN            *
* Description: Copy of ZCA_CHECK_RELEASE_TR, rewritten with local      *
*              classes (lcl_main / lcl_singleton). No FORM routine.    *
*----------------------------------------------------------------------*

REPORT zca_check_release_tr_temp.

*----------------------------------------------------------------------
* TYPES
*----------------------------------------------------------------------
TYPES:
  gtt_display TYPE ztt_display_tr,

  BEGIN OF gty_template_qa,
    seq_no     TYPE i,
    trkorr     TYPE trkorr,
    as4text    TYPE as4text,
    team       TYPE zde_team,
    as4user    TYPE as4user,
    email      TYPE adr6-smtp_addr,
    trfunction TYPE zde_trfunction,
    target     TYPE tarsystem,
  END OF gty_template_qa,
  gtt_template_qa TYPE STANDARD TABLE OF gty_template_qa WITH EMPTY KEY,

  BEGIN OF gty_template_ps4,
    seq_no     TYPE i,
    trkorr     TYPE trkorr,
    as4text    TYPE as4text,
    date       TYPE datum,
    time       TYPE zde_time,
    team       TYPE zde_team,
    as4user    TYPE as4user,
    email      TYPE adr6-smtp_addr,
    trfunction TYPE zde_trfunction,
    target     TYPE tarsystem,
  END OF gty_template_ps4,
  gtt_template_ps4 TYPE STANDARD TABLE OF gty_template_ps4 WITH EMPTY KEY,

  BEGIN OF gty_header,
    string TYPE char50,
  END OF gty_header,
  gtt_header TYPE STANDARD TABLE OF gty_header WITH EMPTY KEY,

  BEGIN OF gty_user,
    bname      TYPE usr21-bname,
    addrnumber TYPE usr21-addrnumber,
    smtp_addr  TYPE adr6-smtp_addr,
  END OF gty_user,
  gtt_user  TYPE STANDARD TABLE OF gty_user WITH EMPTY KEY,

  gtt_dd07v TYPE STANDARD TABLE OF dd07v WITH EMPTY KEY,

  BEGIN OF gty_jira_mention,
    id   TYPE string,
    name TYPE string,
  END OF gty_jira_mention,
  gtt_jira_mention TYPE STANDARD TABLE OF gty_jira_mention WITH EMPTY KEY,

  "index baris grid yang sedang di-drag
  gtt_row_index    TYPE STANDARD TABLE OF i WITH EMPTY KEY.

*----------------------------------------------------------------------
* DATA - hanya dummy select-option dan field dynpro 1010
*----------------------------------------------------------------------
DATA: gw_trheader   TYPE trheader          ##NEEDED.
DATA: gw_entry_time TYPE zst_time_entry.   "dibaca dynpro 1010
"gv_t01 dideklarasikan implisit oleh SELECTION-SCREEN ... FRAME TITLE

*----------------------------------------------------------------------
* PARAMETERS & SELECT-OPTIONS
*----------------------------------------------------------------------
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE gv_t01.
  SELECT-OPTIONS: s_trno  FOR gw_trheader-trkorr  NO INTERVALS,
                  s_serch FOR gw_trheader-as4text NO INTERVALS
                                                  OBLIGATORY,
                  s_owner FOR gw_trheader-as4user NO-EXTENSION
                                                  NO INTERVALS
                                                  MODIF ID md1.
SELECTION-SCREEN END OF BLOCK b1.

*----------------------------------------------------------------------
* CLASS DEFINITION
*----------------------------------------------------------------------
CLASS lcl_main DEFINITION FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS:
      gc_target_qs4 TYPE char3    VALUE 'QS4',
      gc_target_ps4 TYPE char3    VALUE 'PS4',
      gc_target_ds4 TYPE char3    VALUE 'DS4',
      gc_screen_tpl TYPE sy-dynnr VALUE '1010'.

    METHODS:
      constructor,
      initialize,
      execute_foroground,
      execute_background,
      pbo_template,
      set_screen,
      pai_template,

      "! Function code GUI status ZSTANDARD, dipanggil dari AT USER-COMMAND
      user_command IMPORTING iv_ucomm TYPE sy-ucomm,

      "! Lepas grid supaya tidak ikut tampil di selection screen
      free_grid,

      on_double_click FOR EVENT double_click OF cl_gui_alv_grid
        IMPORTING e_row,
      on_hotspot_click FOR EVENT hotspot_click OF cl_gui_alv_grid
        IMPORTING e_row_id,
      on_drag FOR EVENT ondrag OF cl_gui_alv_grid
        IMPORTING e_row e_dragdropobj,
      on_drop FOR EVENT ondrop OF cl_gui_alv_grid
        IMPORTING e_row e_dragdropobj.

  PRIVATE SECTION.
    CONSTANTS:
      gc_rfc_qs4     TYPE rfcdest        VALUE 'QS4CLNT300_ALE',
      gc_rfc_ps4     TYPE rfcdest        VALUE 'PS4CLNT300_ALE',
      gc_rfc_ds4     TYPE rfcdes-rfcdest VALUE 'DS4CLNT110_ALE',
      gc_dom_trstat  TYPE dd07l-domname  VALUE 'TRSTATUS',
      gc_dom_trfunc  TYPE dd07l-domname  VALUE 'TRFUNCTION',
      gc_gui_status  TYPE sy-pfkey         VALUE 'ZSTANDARD',

      "function code sesuai GUI status ZSTANDARD
      gc_fc_release  TYPE salv_de_function VALUE '&UPD',
      gc_fc_check    TYPE salv_de_function VALUE '&CHK',
      gc_fc_all      TYPE salv_de_function VALUE 'ALL',
      gc_fc_tpl_qs4  TYPE salv_de_function VALUE '&QA',
      gc_fc_tpl_ps4  TYPE salv_de_function VALUE '&PS4',
      gc_fc_upd_cacr TYPE salv_de_function VALUE '&UPD_CACR',
      gc_fc_upd_jira TYPE salv_de_function VALUE '&REQ_JIRA',
      "keluar dari list; ZSTANDARD disalin dari status standar SALV
      gc_fc_back     TYPE sy-ucomm         VALUE '&F03',
      gc_fc_exit     TYPE sy-ucomm         VALUE '&F15',
      gc_fc_cancel   TYPE sy-ucomm         VALUE '&F12',
      gc_display_str TYPE dd02l-tabname    VALUE 'ZST_DISPLAY_TR',
      gc_dd_flavor   TYPE cndd_flavor      VALUE 'LINE',
      gc_text_qs4    TYPE thead-tdname   VALUE 'ZTEMPLATE_QS4',
      gc_text_ps4    TYPE thead-tdname   VALUE 'ZTEMPLATE_PS4',
      gc_sender_mail TYPE ad_smtpadr     VALUE 'sap.development@erajaya.com',
      gc_recv_mail   TYPE ad_smtpadr     VALUE 'gregorius.napis@erajaya.com',
      gc_team        TYPE zde_team       VALUE 'Technical',
      gc_prefix_text TYPE tdobname       VALUE 'ZCA_REQUEST_(CLIENT)_(ENDPOINT)',
      gc_object      TYPE thead-tdobject VALUE 'TEXT',
      gc_id          TYPE thead-tdid     VALUE 'ST'.

    DATA:
      mt_trdata       TYPE gtt_display,
      mt_trdata_child TYPE gtt_display,
      mo_grid         TYPE REF TO cl_gui_alv_grid,
      mo_dragdrop     TYPE REF TO cl_dragdrop,
      mt_drag_rows    TYPE gtt_row_index,
      mv_export       TYPE abap_bool,
      mv_email        TYPE abap_bool,
      mv_jira         TYPE abap_bool.

    METHODS:
      get_tr_data EXPORTING VALUE(rt_trdata)       TYPE gtt_display
                            VALUE(rt_trdata_child) TYPE gtt_display,

      get_tr_remote IMPORTING iv_rfcdest       TYPE rfcdest
                              ir_trno          TYPE ucon_tr_req_range
                    RETURNING VALUE(rt_trdata) TYPE gtt_display,

      get_domain_text IMPORTING iv_domname      TYPE dd07l-domname
                      RETURNING VALUE(rt_dd07v) TYPE gtt_dd07v,

      set_last_location IMPORTING iw_trdata         TYPE LINE OF gtt_display
                                  it_trdata_qs4     TYPE gtt_display
                                  it_trdata_ps4     TYPE gtt_display
                        RETURNING VALUE(rv_lastloc) TYPE tarsystem,

      check_cr_maintained IMPORTING it_trdata TYPE gtt_display,

      get_crnumber IMPORTING iw_trdata          TYPE LINE OF gtt_display
                   RETURNING VALUE(rv_crnumber) TYPE zde_crnumber,

      get_user_email RETURNING VALUE(rt_user) TYPE gtt_user,

      display_data,

      "! Field catalog dari ZST_DISPLAY_TR plus penyesuaian kolom
      get_fieldcat RETURNING VALUE(rt_fcat) TYPE lvc_t_fcat,

      "! Handle drag & drop baris untuk layout grid
      get_dragdrop_handle RETURNING VALUE(rv_handle) TYPE i,

      refresh_grid,

      "! Pindahkan baris hasil drag ke posisi drop, kembalikan index barunya
      move_rows IMPORTING it_rows         TYPE gtt_row_index
                          iv_target       TYPE i
                RETURNING VALUE(rt_moved) TYPE gtt_row_index,

      release_tr,
      call_check,

      tick_untick IMPORTING iv_row TYPE i,

      create_template IMPORTING iv_target TYPE char3,

      download_template IMPORTING iv_target       TYPE char3
                                  it_template_qa  TYPE gtt_template_qa
                                  it_template_ps4 TYPE gtt_template_ps4
                                  it_header       TYPE gtt_header,

      send_email IMPORTING iv_xstring TYPE xstring
                           iv_target  TYPE char3,

      update_cacr IMPORTING iv_lastloc TYPE char3,

      "! Komentar approval Jira (ADF), satu tableRow per TR terpilih.
      "! Baris memakai gtt_template_ps4 karena kolomnya superset dari QS4.
      build_jira_comment IMPORTING iv_target      TYPE char3
                                   it_rows        TYPE gtt_template_ps4
                         RETURNING VALUE(rv_json) TYPE string,

      "! Kirim komentar approval ke Jira lewat ZFI_CA_SEND_REQ_APPRV_JIR
      post_jira_approval IMPORTING iv_target   TYPE char3
                                   iv_endpoint TYPE char20
                                   it_rows     TYPE gtt_template_ps4,

      "! Pecah payload JSON jadi tdline tanpa blank di ujung baris
      json_to_lines IMPORTING iv_json         TYPE string
                    RETURNING VALUE(rt_lines) TYPE text_lines,

      get_jira_lead  RETURNING VALUE(rw_mention) TYPE gty_jira_mention,
      get_jira_head  RETURNING VALUE(rw_mention) TYPE gty_jira_mention,
      get_jira_basis RETURNING VALUE(rt_mention) TYPE gtt_jira_mention,

      jira_escape IMPORTING iv_text        TYPE clike
                  RETURNING VALUE(rv_text) TYPE string,

      jira_text IMPORTING iv_text        TYPE clike
                          iv_mailto      TYPE abap_bool DEFAULT abap_false
                RETURNING VALUE(rv_node) TYPE string,

      jira_mention_node IMPORTING iw_mention     TYPE gty_jira_mention
                        RETURNING VALUE(rv_node) TYPE string,

      jira_paragraph IMPORTING it_nodes       TYPE string_table
                     RETURNING VALUE(rv_node) TYPE string,

      jira_cell IMPORTING iv_text        TYPE clike
                          iv_mailto      TYPE abap_bool DEFAULT abap_false
                RETURNING VALUE(rv_node) TYPE string,

      jira_row IMPORTING it_cells       TYPE string_table
               RETURNING VALUE(rv_node) TYPE string,

      save_to_table IMPORTING iv_target  TYPE char3
                              iw_entry   TYPE zst_time_entry
                              it_content TYPE text_lines,

      save_text IMPORTING iv_name    TYPE tdobname
                          it_content TYPE text_lines,

      get_text_name IMPORTING iv_target      TYPE char3
                              iw_entry       TYPE zst_time_entry
                    RETURNING VALUE(rv_name) TYPE tdobname.
ENDCLASS.

CLASS lcl_singleton DEFINITION FINAL CREATE PRIVATE.

  PUBLIC SECTION.
    CLASS-DATA go_main TYPE REF TO lcl_main READ-ONLY.
    CLASS-METHODS:
      create,
      execute,
      pbo_template,
      set_screen,
      pai_template,
      user_command IMPORTING iv_ucomm TYPE sy-ucomm,
      free_grid.

ENDCLASS.

*----------------------------------------------------------------------
* CLASS IMPLEMENTATION
*----------------------------------------------------------------------
CLASS lcl_main IMPLEMENTATION.

  METHOD constructor.
    gv_t01 = 'Selection' ##NO_TEXT.
  ENDMETHOD.

  METHOD initialize.
    s_owner[] = VALUE #(
      ( sign = imphs_c_sign-including option = imphs_c_option-equal low = sy-uname ) ).

    s_serch[] = VALUE #(
      ( sign   = imphs_c_sign-including
        option = imphs_c_option-contains_pattern
        low    = space ) ).
  ENDMETHOD.

  METHOD execute_foroground.
    get_tr_data(
      IMPORTING
        rt_trdata       = mt_trdata
        rt_trdata_child = mt_trdata_child
    ).

    IF mt_trdata IS INITIAL.
      MESSAGE 'Data Not Found' TYPE fiehc_con_msgty_i
              DISPLAY LIKE fiehc_con_msgty_e ##NO_TEXT.
      RETURN.
    ENDIF.

    display_data( ).
  ENDMETHOD.

  METHOD execute_background.

  ENDMETHOD.

  METHOD get_tr_data.
    DATA lr_search TYPE RANGE OF e07t-as4text.

    lr_search = VALUE #( FOR lw_search IN s_serch[] (
      sign   = imphs_c_sign-including
      option = imphs_c_option-contains_pattern
      low    = |*{ lw_search-low }*| ) ).

    CALL FUNCTION 'ZCA_FM_GET_TR'
      EXPORTING
        ir_trno   = s_trno[]
        ir_owner  = s_owner[]
        ir_seach  = lr_search[]
      IMPORTING
        et_trdata = rt_trdata.

    IF rt_trdata IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lr_trno) = VALUE ucon_tr_req_range( FOR lw_trdata IN rt_trdata
      ( sign = imphs_c_sign-including option = imphs_c_option-equal low = lw_trdata-trkorr ) ).

    DATA(lt_trdata_qs4) = get_tr_remote( iv_rfcdest = gc_rfc_qs4
                                         ir_trno    = lr_trno ).
    DATA(lt_trdata_ps4) = get_tr_remote( iv_rfcdest = gc_rfc_ps4
                                         ir_trno    = lr_trno ).

    DATA(lt_trstat_dom) = get_domain_text( gc_dom_trstat ).

    check_cr_maintained( rt_trdata ).

    LOOP AT rt_trdata ASSIGNING FIELD-SYMBOL(<lf_trdata>).
      <lf_trdata>-lastloc = set_last_location( iw_trdata     = <lf_trdata>
                                               it_trdata_qs4 = lt_trdata_qs4
                                               it_trdata_ps4 = lt_trdata_ps4 ).

      READ TABLE lt_trstat_dom INTO DATA(lw_trstat)
        WITH KEY domvalue_l = <lf_trdata>-trstatus
        BINARY SEARCH.
      IF sy-subrc = 0.
        <lf_trdata>-status = lw_trstat-ddtext.
      ENDIF.

      IF <lf_trdata>-strkorr IS NOT INITIAL.
        APPEND <lf_trdata> TO rt_trdata_child.
      ENDIF.

    ENDLOOP.

    DELETE rt_trdata WHERE strkorr IS NOT INITIAL.

    SORT : rt_trdata ASCENDING BY trkorr,
           rt_trdata_child ASCENDING BY strkorr.
  ENDMETHOD.

  METHOD get_tr_remote.
    CALL FUNCTION 'ZCA_FM_GET_TR' DESTINATION iv_rfcdest
      EXPORTING
        ir_trno               = ir_trno
        ir_owner              = s_owner[]
      IMPORTING
        et_trdata             = rt_trdata
      EXCEPTIONS
        system_failure        = 1
        communication_failure = 2
        resource_failure      = 3
        ##FM_SUBRC_OK.
    IF sy-subrc <> 0.
      "sistem remote tidak terhubung: TR dianggap belum sampai di sana
      CLEAR rt_trdata.
      RETURN.
    ENDIF.

    SORT rt_trdata BY trkorr.
  ENDMETHOD.

  METHOD get_domain_text.
    CALL FUNCTION 'DD_DOMVALUES_GET'
      EXPORTING
        domname        = iv_domname
        text           = abap_true
        langu          = sy-langu
      TABLES
        dd07v_tab      = rt_dd07v
      EXCEPTIONS
        wrong_textflag = 1
        OTHERS         = 2.
    IF sy-subrc <> 0.
      CLEAR rt_dd07v.
      RETURN.
    ENDIF.

    SORT rt_dd07v BY domvalue_l.
  ENDMETHOD.

  METHOD set_last_location.
    rv_lastloc = gc_target_ds4.

    IF line_exists( it_trdata_ps4[ trkorr = iw_trdata-trkorr ] ) OR
     ( iw_trdata-strkorr IS NOT INITIAL AND
       line_exists( it_trdata_ps4[ trkorr = iw_trdata-strkorr ] ) ).
      rv_lastloc = gc_target_ps4.
      RETURN.
    ENDIF.

    IF line_exists( it_trdata_qs4[ trkorr = iw_trdata-trkorr ] ) OR
     ( iw_trdata-strkorr IS NOT INITIAL AND
       line_exists( it_trdata_qs4[ trkorr = iw_trdata-strkorr ] ) ).
      rv_lastloc = gc_target_qs4.
    ENDIF.
  ENDMETHOD.

  METHOD check_cr_maintained.
    DATA lt_crnumber TYPE STANDARD TABLE OF zde_crnumber WITH EMPTY KEY.

    LOOP AT it_trdata INTO DATA(lw_trdata) WHERE strkorr IS INITIAL.
      APPEND get_crnumber( lw_trdata ) TO lt_crnumber.
    ENDLOOP.

    IF lt_crnumber IS INITIAL.
      RETURN.
    ENDIF.

    SELECT @abap_true
      FROM ztca_chgreq AS a
      INNER JOIN @lt_crnumber AS b ON a~crnumber = b~table_line
      ORDER BY a~crnumber
      INTO TABLE @DATA(lt_ztca_chgreq) ##DB_FEATURE_MODE[ITABS_IN_FROM_CLAUSE].
    IF sy-subrc <> 0 OR lt_ztca_chgreq IS INITIAL.
      MESSAGE 'CR not yet maintain in ZCACR01' TYPE fiehc_con_msgty_i ##NO_TEXT.
    ENDIF.
  ENDMETHOD.

  METHOD get_crnumber.
    DATA(lv_prefix) = COND string( WHEN iw_trdata-as4text CS 'IRQ' THEN 'IRQ-'
                                   ELSE '#' ) ##NO_TEXT.

    rv_crnumber = |{ lv_prefix }{ VALUE #( s_serch[ 1 ]-low OPTIONAL ) }|.
  ENDMETHOD.

  METHOD get_user_email.
    SELECT a~bname,
           a~addrnumber,
           b~smtp_addr
      FROM usr21 AS a
      INNER JOIN adr6 AS b ON a~addrnumber = b~addrnumber
                          AND a~persnumber = b~persnumber
      WHERE a~bname = @sy-uname
      ORDER BY a~bname
      INTO TABLE @rt_user.
    IF sy-subrc <> 0.
      CLEAR rt_user.
    ENDIF.
  ENDMETHOD.

  METHOD display_data.
    IF mo_grid IS BOUND.
      refresh_grid( ).
      RETURN.
    ENDIF.

    "CREATE OBJECT karena constructor grid memakai classic exception
    CREATE OBJECT mo_grid
      EXPORTING
        i_parent          = cl_gui_container=>default_screen
      EXCEPTIONS
        error_cntl_create = 1
        error_cntl_init   = 2
        error_cntl_link   = 3
        error_dp_create   = 4
        OTHERS            = 5.
    IF sy-subrc <> 0.
      MESSAGE 'ALV grid tidak bisa dibuat' TYPE fiehc_con_msgty_i
              DISPLAY LIKE fiehc_con_msgty_e ##NO_TEXT.
      RETURN.
    ENDIF.

    "sel_mode A: row selector aktif, dipakai untuk memilih baris yang di-drag
    DATA(lw_layout) = VALUE lvc_s_layo( zebra      = abap_true
                                        sel_mode   = 'A'
                                        s_dragdrop = VALUE #( row_ddid = get_dragdrop_handle( ) ) ).

    SET HANDLER: me->on_double_click  FOR mo_grid,
                 me->on_hotspot_click FOR mo_grid,
                 me->on_drag          FOR mo_grid,
                 me->on_drop          FOR mo_grid.

    DATA(lt_fcat) = get_fieldcat( ).

    mo_grid->set_table_for_first_display(
      EXPORTING
        is_layout                     = lw_layout
        is_variant                    = VALUE disvariant( report = sy-repid )
        i_save                        = 'A'
      CHANGING
        it_outtab                     = mt_trdata
        it_fieldcatalog               = lt_fcat
      EXCEPTIONS
        invalid_parameter_combination = 1
        program_error                 = 2
        too_many_lines                = 3
        OTHERS                        = 4 ).
    IF sy-subrc <> 0.
      MESSAGE 'ALV grid tidak bisa ditampilkan' TYPE fiehc_con_msgty_i
              DISPLAY LIKE fiehc_con_msgty_e ##NO_TEXT.
      free_grid( ).
      RETURN.
    ENDIF.

    "grid menempel di default screen; list kosong ini yang membawa layar
    "dan GUI status-nya, function code masuk lewat AT USER-COMMAND
    SET PF-STATUS gc_gui_status.
    WRITE space.
  ENDMETHOD.

  METHOD get_fieldcat.
    CALL FUNCTION 'LVC_FIELDCATALOG_MERGE'
      EXPORTING
        i_structure_name       = gc_display_str
      CHANGING
        ct_fieldcat            = rt_fcat
      EXCEPTIONS
        inconsistent_interface = 1
        program_error          = 2
        OTHERS                 = 3.
    IF sy-subrc <> 0.
      CLEAR rt_fcat.
      RETURN.
    ENDIF.

    LOOP AT rt_fcat ASSIGNING FIELD-SYMBOL(<lf_fcat>).
      CASE <lf_fcat>-fieldname.
        WHEN 'CHECKBOX'.
          "hotspot, bukan edit: toggle tetap lewat tick_untick seperti versi SALV
          <lf_fcat>-checkbox  = abap_true.
          <lf_fcat>-hotspot   = abap_true.
          <lf_fcat>-outputlen = 5.
        WHEN 'LASTLOC'.
          <lf_fcat>-scrtext_m = 'Last Loc' ##NO_TEXT.
          <lf_fcat>-scrtext_l = 'Last Location' ##NO_TEXT.
          <lf_fcat>-coltext   = 'Last Location' ##NO_TEXT.
        WHEN 'STATUS'.
          <lf_fcat>-scrtext_m = 'Status' ##NO_TEXT.
          <lf_fcat>-scrtext_l = 'Status' ##NO_TEXT.
          <lf_fcat>-coltext   = 'Status' ##NO_TEXT.
        WHEN 'MESSAGE'.
          <lf_fcat>-outputlen = 50.
      ENDCASE.
    ENDLOOP.

    "kolom checkbox selalu paling kiri
    READ TABLE rt_fcat INTO DATA(lw_checkbox) WITH KEY fieldname = 'CHECKBOX'.
    IF sy-subrc = 0.
      DELETE rt_fcat INDEX sy-tabix.
      INSERT lw_checkbox INTO rt_fcat INDEX 1.
    ENDIF.

    LOOP AT rt_fcat ASSIGNING <lf_fcat>.
      <lf_fcat>-col_pos = sy-tabix.
    ENDLOOP.
  ENDMETHOD.

  METHOD get_dragdrop_handle.
    mo_dragdrop = NEW cl_dragdrop( ).

    "baris grid jadi sumber sekaligus target: reorder di dalam grid yang sama
    mo_dragdrop->add(
      EXPORTING
        flavor          = gc_dd_flavor
        dragsrc         = abap_true
        droptarget      = abap_true
        effect          = cl_dragdrop=>move
      EXCEPTIONS
        already_defined = 1
        obj_invalid     = 2
        OTHERS          = 3 ).
    IF sy-subrc <> 0.
      RETURN.   "handle 0: grid tampil tanpa drag & drop
    ENDIF.

    mo_dragdrop->get_handle(
      IMPORTING
        handle      = rv_handle
      EXCEPTIONS
        obj_invalid = 1
        OTHERS      = 2 ).
    IF sy-subrc <> 0.
      CLEAR rv_handle.
    ENDIF.
  ENDMETHOD.

  METHOD refresh_grid.
    IF mo_grid IS NOT BOUND.
      RETURN.
    ENDIF.

    mo_grid->refresh_table_display(
      EXPORTING
        is_stable = VALUE #( row = abap_true col = abap_true )
      EXCEPTIONS
        finished  = 1
        OTHERS    = 2 ).
    IF sy-subrc <> 0.
      MESSAGE 'ALV grid gagal di-refresh' TYPE fiehc_con_msgty_s ##NO_TEXT.
    ENDIF.
  ENDMETHOD.

  METHOD free_grid.
    IF mo_grid IS NOT BOUND.
      RETURN.
    ENDIF.

    mo_grid->free(
      EXCEPTIONS
        cntl_error        = 1
        cntl_system_error = 2
        OTHERS            = 3 ).
    IF sy-subrc <> 0.
      "control sudah lepas dari frontend; cukup buang referensinya
      CLEAR sy-subrc.
    ENDIF.

    FREE: mo_grid, mo_dragdrop.
    CLEAR mt_drag_rows.
  ENDMETHOD.

  METHOD user_command.
    CASE iv_ucomm.
      WHEN gc_fc_release.
        release_tr( ).
        refresh_grid( ).
      WHEN gc_fc_check.
        call_check( ).
      WHEN gc_fc_all.
        tick_untick( 0 ).
        refresh_grid( ).
      WHEN gc_fc_tpl_qs4.
        create_template( gc_target_qs4 ).
      WHEN gc_fc_tpl_ps4.
        create_template( gc_target_ps4 ).
      WHEN gc_fc_upd_jira.

*      WHEN
      WHEN gc_fc_back OR gc_fc_cancel.
        free_grid( ).
        LEAVE TO SCREEN 0.
      WHEN gc_fc_exit.
        free_grid( ).
        LEAVE PROGRAM.
    ENDCASE.
  ENDMETHOD.

  METHOD on_double_click.
    READ TABLE mt_trdata INTO DATA(lw_trdata) INDEX e_row-index.
    IF sy-subrc = 0.
      SET PARAMETER ID 'KOR' FIELD lw_trdata-trkorr.
      CALL TRANSACTION 'SE01' AND SKIP FIRST SCREEN.
    ENDIF.
  ENDMETHOD.

  METHOD on_hotspot_click.
    tick_untick( CONV #( e_row_id-index ) ).
    refresh_grid( ).
  ENDMETHOD.

  METHOD on_drag.
    mo_grid->get_selected_rows( IMPORTING et_index_rows = DATA(lt_selected) ).

    "baris yang di-drag termasuk seleksi: semua baris terpilih ikut pindah;
    "kalau tidak, hanya baris yang di-drag
    mt_drag_rows = VALUE #( FOR lw_selected IN lt_selected WHERE ( rowtype IS INITIAL )
                            ( CONV #( lw_selected-index ) ) ).
    DATA(lv_drag_row) = CONV i( e_row-index ).
    IF NOT line_exists( mt_drag_rows[ table_line = lv_drag_row ] ).
      mt_drag_rows = VALUE #( ( lv_drag_row ) ).
    ENDIF.
    SORT mt_drag_rows BY table_line.

    e_dragdropobj->object = me.
  ENDMETHOD.

  METHOD on_drop.
    "drop yang tidak berasal dari grid ini, atau drag tanpa baris: batalkan
    IF e_dragdropobj->object <> me OR mt_drag_rows IS INITIAL.
      e_dragdropobj->abort( ).
      RETURN.
    ENDIF.

    DATA(lt_new_rows) = move_rows( it_rows   = mt_drag_rows
                                   iv_target = CONV #( e_row-index ) ).
    CLEAR mt_drag_rows.

    IF lt_new_rows IS INITIAL.
      e_dragdropobj->abort( ).
      RETURN.
    ENDIF.

    "sort aktif akan mengurutkan ulang dan menimpa urutan manual
    mo_grid->set_sort_criteria(
      EXPORTING
        it_sort                   = VALUE #( )
      EXCEPTIONS
        no_fieldcatalog_available = 1
        OTHERS                    = 2 ).
    IF sy-subrc <> 0.
      MESSAGE 'Sort grid tidak bisa direset' TYPE fiehc_con_msgty_s ##NO_TEXT.
    ENDIF.

    refresh_grid( ).

    "baris yang dipindah tetap terpilih di posisi barunya
    mo_grid->set_selected_rows(
      it_index_rows = VALUE #( FOR lv_row IN lt_new_rows ( index = lv_row ) ) ).
  ENDMETHOD.

  METHOD move_rows.
    DATA(lv_lines) = lines( mt_trdata ).

    "drop di area kosong di bawah data berarti pindah ke paling bawah
    DATA(lv_target) = COND i( WHEN iv_target BETWEEN 1 AND lv_lines THEN iv_target
                              ELSE lv_lines ).

    "drop ke salah satu baris yang sedang dipindah: tidak ada yang berubah
    IF it_rows IS INITIAL OR line_exists( it_rows[ table_line = lv_target ] ).
      RETURN.
    ENDIF.

    DATA(lt_moved) = VALUE gtt_display( FOR lv_index IN it_rows
                                        WHERE ( table_line BETWEEN 1 AND lv_lines )
                                        ( mt_trdata[ lv_index ] ) ).

    "posisi target dihitung ulang setelah baris yang dipindah dihapus.
    "Bergerak ke bawah: sisip setelah baris target; ke atas: sebelum.
    DATA(lv_above) = REDUCE i( INIT lv_count = 0
                               FOR lv_index IN it_rows WHERE ( table_line < lv_target )
                               NEXT lv_count = lv_count + 1 ).

    DATA(lv_insert) = COND i( WHEN lv_target > it_rows[ 1 ] THEN lv_target - lv_above + 1
                              ELSE lv_target - lv_above ).

    "hapus dari bawah supaya index di atasnya tidak bergeser
    DATA(lv_count_rows) = lines( it_rows ).
    DO lv_count_rows TIMES.
      DELETE mt_trdata INDEX it_rows[ lv_count_rows - sy-index + 1 ].
    ENDDO.

    INSERT LINES OF lt_moved INTO mt_trdata INDEX lv_insert.

    rt_moved = VALUE #( FOR lv_new = lv_insert WHILE lv_new < lv_insert + lines( lt_moved )
                        ( lv_new ) ).
  ENDMETHOD.

  METHOD tick_untick.
    DATA(lv_to) = COND i( WHEN iv_row > 0 THEN iv_row
                          ELSE lines( mt_trdata ) ).

    LOOP AT mt_trdata ASSIGNING FIELD-SYMBOL(<lf_trdata>) FROM iv_row TO lv_to.
      <lf_trdata>-checkbox = COND #( WHEN <lf_trdata>-checkbox IS INITIAL THEN abap_true
                                     ELSE abap_false ).
    ENDLOOP.
  ENDMETHOD.

  METHOD release_tr.
    DATA: lv_es_request       TYPE trwbo_request ##NEEDED,
          lt_et_deleted_tasks TYPE trwbo_t_e070  ##NEEDED.

    DATA(lt_trdata) = mt_trdata.
    SORT lt_trdata BY strkorr DESCENDING.

    DATA(lv_selected) = abap_false.

    LOOP AT lt_trdata INTO DATA(lw_trdata) WHERE checkbox = abap_true.
      lv_selected = abap_true.

      READ TABLE mt_trdata_child TRANSPORTING NO FIELDS
        WITH KEY strkorr = lw_trdata-trkorr
        BINARY SEARCH.
      IF sy-subrc = 0.
        LOOP AT mt_trdata_child INTO DATA(lw_trdata_child) FROM sy-tabix.
          IF lw_trdata_child-strkorr <> lw_trdata-trkorr.
            EXIT.
          ENDIF.
          CALL FUNCTION 'TR_RELEASE_REQUEST'
            EXPORTING
              iv_trkorr                  = lw_trdata_child-trkorr
            IMPORTING
              es_request                 = lv_es_request
              et_deleted_tasks           = lt_et_deleted_tasks
            EXCEPTIONS
              cts_initialization_failure = 1
              enqueue_failed             = 2
              no_authorization           = 3
              invalid_request            = 4
              request_already_released   = 5
              repeat_too_early           = 6
              error_in_export_methods    = 7
              object_check_error         = 8
              docu_missing               = 9
              db_access_error            = 10
              action_aborted_by_user     = 11
              export_failed              = 12
              OTHERS                     = 13
              ##FM_SUBRC_OK.
        ENDLOOP.
      ENDIF.

      CALL FUNCTION 'TR_RELEASE_REQUEST'
        EXPORTING
          iv_trkorr                  = lw_trdata-trkorr
        IMPORTING
          es_request                 = lv_es_request
          et_deleted_tasks           = lt_et_deleted_tasks
        EXCEPTIONS
          cts_initialization_failure = 1
          enqueue_failed             = 2
          no_authorization           = 3
          invalid_request            = 4
          request_already_released   = 5
          repeat_too_early           = 6
          error_in_export_methods    = 7
          object_check_error         = 8
          docu_missing               = 9
          db_access_error            = 10
          action_aborted_by_user     = 11
          export_failed              = 12
          OTHERS                     = 13
          ##FM_SUBRC_OK.

      "pesan sukses maupun gagal sama-sama ditampilkan di kolom MESSAGE
      MESSAGE ID sy-msgid TYPE fiehc_con_msgty_i NUMBER sy-msgno
              WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4
              INTO lw_trdata-message.

      ASSIGN mt_trdata[ trkorr = lw_trdata-trkorr ] TO FIELD-SYMBOL(<lf_trdata>).
      IF sy-subrc = 0.
        <lf_trdata>-message = lw_trdata-message.
      ENDIF.

      CLEAR lw_trdata.

    ENDLOOP.

    IF lv_selected = abap_false.
      MESSAGE 'Please Choose TR' TYPE fiehc_con_msgty_i
              DISPLAY LIKE fiehc_con_msgty_e ##NO_TEXT.
    ENDIF.
  ENDMETHOD.

  METHOD call_check.
    DATA(lt_sval) = VALUE ty_sval(
      ( tabname = 'RFCDES' fieldname = 'RFCDEST' fieldtext = 'Destination' ) ) ##NO_TEXT.

    CALL FUNCTION 'POPUP_GET_VALUES'
      EXPORTING
        popup_title     = 'Target Client'
      TABLES
        fields          = lt_sval
      EXCEPTIONS
        error_in_fields = 1
        OTHERS          = 2
        ##FM_SUBRC_OK.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    DATA(lv_target) = CONV rfcdes-rfcdest( VALUE #( lt_sval[ 1 ]-value OPTIONAL ) ).
    IF lv_target IS INITIAL.
      MESSAGE 'Wrong Target' TYPE fiehc_con_msgty_i
              DISPLAY LIKE fiehc_con_msgty_e ##NO_TEXT.
      RETURN.
    ENDIF.

    DATA(lr_trkor) = VALUE rsdsselopt_t(
      FOR lw_trdata IN mt_trdata WHERE ( checkbox = abap_true )
      ( sign   = imphs_c_sign-including
        option = imphs_c_option-equal
        low    = lw_trdata-trkorr ) ).

    IF lr_trkor IS INITIAL.
      MESSAGE 'Please Choose TR' TYPE fiehc_con_msgty_i
              DISPLAY LIKE fiehc_con_msgty_e ##NO_TEXT.
      RETURN.
    ENDIF.

    CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
      EXPORTING
        percentage = 75
        text       = 'Check Running...' ##NO_TEXT.

    SUBMIT /sdf/cmo_tr_check
      WITH p_source = gc_rfc_ds4
      WITH p_target = lv_target
      WITH r_prj_co = abap_true
      WITH p_ori_tr IN lr_trkor
      WITH p_crsref = abap_true
      WITH p_dgp    = abap_true
      WITH p_swcomp = abap_true
      WITH p_imptim = abap_true
      WITH p_oichck = abap_true
      AND RETURN.
  ENDMETHOD.

  METHOD pbo_template.
    CLEAR gw_entry_time.
  ENDMETHOD.

  METHOD set_screen.
    IF sy-ucomm = '&PS4'.
      LOOP AT SCREEN.
        IF screen-name = 'GW_ENTRY_TIME-DATE'
          OR screen-name = 'GW_ENTRY_TIME-TIME'.
          screen-required = '1'.
          MODIFY SCREEN.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD pai_template.
    CASE sy-ucomm.
      WHEN 'EXPORT'.
        mv_export = abap_true.
      WHEN '&EMAIL'.
        mv_email = abap_true.
      WHEN '&JIRA'.
        IF gw_entry_time-endpoint IS INITIAL.
          DATA(lv_error) = abap_true.
          MESSAGE 'Fill Target Endpoint' TYPE 'S'.
        ELSEIF gw_entry_time-approver IS INITIAL.
          lv_error = abap_true.
          MESSAGE 'Fill Approver' TYPE 'S'.
        ELSE.
          mv_jira = abap_true.
        ENDIF.
      WHEN OTHERS.
        "CANCEL atau window ditutup: tidak ada efek samping
        CLEAR: mv_export, mv_email, mv_jira.
    ENDCASE.
    IF lv_error = abap_false.
      LEAVE TO SCREEN 0.
    ENDIF.
  ENDMETHOD.

  METHOD create_template.
    DATA: lt_template_qa  TYPE gtt_template_qa,
          lt_template_ps4 TYPE gtt_template_ps4,
          lt_header       TYPE gtt_header.

    DATA(lt_user)  = get_user_email( ).
    DATA(lt_dd07v) = get_domain_text( gc_dom_trfunc ).

    "flag diisi ulang oleh dynpro 1010, jangan terbawa dari pemanggilan sebelumnya
    CLEAR: mv_export, mv_email, mv_jira.

    CALL SCREEN gc_screen_tpl STARTING AT 20 10
                              ENDING AT 25 20.
    IF mv_export = abap_false AND mv_email = abap_false AND mv_jira = abap_false.
      RETURN.
    ENDIF.

    DATA(lv_no) = 0.
    LOOP AT mt_trdata INTO DATA(lw_trdata) WHERE strkorr  IS INITIAL
                                             AND checkbox = abap_true.
      lv_no += 1.

      DATA(lw_user)  = VALUE gty_user( lt_user[ bname = sy-uname ] OPTIONAL ).
      DATA(lw_dd07v) = VALUE dd07v( lt_dd07v[ domvalue_l = lw_trdata-trfunction ] OPTIONAL ).

      IF iv_target = gc_target_qs4.
        APPEND VALUE gty_template_qa(
                 seq_no     = lv_no
                 trkorr     = lw_trdata-trkorr
                 as4text    = lw_trdata-as4text
                 team       = gc_team
                 as4user    = lw_trdata-as4user
                 email      = lw_user-smtp_addr
                 trfunction = lw_dd07v-ddtext
                 target     = 'QS4 300' ) TO lt_template_qa ##NO_TEXT.

        IF lt_header IS INITIAL.
          lt_header = VALUE #( ( string = 'Seq. No.' )
                               ( string = 'Request #' )
                               ( string = 'TR Description' )
                               ( string = 'Team' )
                               ( string = 'Owner/Requestor Name' )
                               ( string = 'Requestor Email ID' )
                               ( string = 'Type' )
                               ( string = 'Target System' ) ) ##NO_TEXT.
        ENDIF.
      ELSE.
        APPEND VALUE gty_template_ps4(
                 seq_no     = lv_no
                 trkorr     = lw_trdata-trkorr
                 as4text    = lw_trdata-as4text
                 date       = |{ gw_entry_time-date }|
                 time       = |{ gw_entry_time-time }|
                 team       = gc_team
                 as4user    = lw_trdata-as4user
                 email      = lw_user-smtp_addr
                 trfunction = lw_dd07v-ddtext
                 target     = 'PS4 300' ) TO lt_template_ps4 ##NO_TEXT.

        IF lt_header IS INITIAL.
          lt_header = VALUE #( ( string = 'Seq. No.' )
                               ( string = 'Request #' )
                               ( string = 'TR Description' )
                               ( string = 'Date' )
                               ( string = 'Time' )
                               ( string = 'Team' )
                               ( string = 'Owner/Requestor Name' )
                               ( string = 'Requestor Email ID' )
                               ( string = 'Type' )
                               ( string = 'Target System' ) ) ##NO_TEXT.
        ENDIF.
      ENDIF.
    ENDLOOP.

    IF lv_no = 0.
      MESSAGE 'Please Choose TR' TYPE fiehc_con_msgty_i
              DISPLAY LIKE fiehc_con_msgty_e ##NO_TEXT.
      RETURN.
    ENDIF.

    IF mv_export = abap_true.
      download_template( iv_target       = iv_target
                         it_template_qa  = lt_template_qa
                         it_template_ps4 = lt_template_ps4
                         it_header       = lt_header ).
      update_cacr( iv_target ).
      CLEAR mv_export.

    ELSEIF mv_email = abap_true.
      DATA(lv_xstring) = NEW zcl_itab_to_excel( )->itab_to_xstring(
        ir_data_ref = COND #( WHEN iv_target = gc_target_ps4 THEN REF #( lt_template_ps4 )
                              WHEN iv_target = gc_target_qs4 THEN REF #( lt_template_qa ) ) ).

      send_email( iv_xstring = lv_xstring
                  iv_target  = iv_target ).
      CLEAR mv_email.

      update_cacr( iv_target ).
    ENDIF.

    IF mv_jira = abap_true.
      "baris Jira memakai tipe PS4 karena kolomnya superset; QS4 di-CORRESPONDING
      DATA(lt_jira_row) = lt_template_ps4.
      IF iv_target = gc_target_qs4.
        lt_jira_row = CORRESPONDING #( lt_template_qa ).
      ENDIF.

      post_jira_approval( iv_target = iv_target
                          iv_endpoint = gw_entry_time-endpoint
                          it_rows   = lt_jira_row ).
      CLEAR mv_jira.
    ENDIF.

  ENDMETHOD.

  METHOD download_template.
    DATA(lv_filename) = CONV rlgrap-filename( space ).

    CALL FUNCTION 'KD_GET_FILENAME_ON_F4'
      EXPORTING
        static    = abap_true
        mask      = '*.XLS'
      CHANGING
        file_name = lv_filename.

    IF lv_filename IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lv_save_filename) = |{ lv_filename }.xls| ##NO_TEXT.

    IF iv_target = gc_target_ps4.
      CALL FUNCTION 'GUI_DOWNLOAD'
        EXPORTING
          filename              = lv_save_filename
          filetype              = 'ASC'
          write_field_separator = abap_true
        TABLES
          data_tab              = it_template_ps4
          fieldnames            = it_header.

    ELSEIF iv_target = gc_target_qs4.
      CALL FUNCTION 'GUI_DOWNLOAD'
        EXPORTING
          filename              = lv_save_filename
          filetype              = 'ASC'
          write_field_separator = abap_true
        TABLES
          data_tab              = it_template_qa
          fieldnames            = it_header.
    ENDIF.
  ENDMETHOD.

  METHOD send_email.
    DATA lv_return TYPE char1.

    DATA(lt_sval) = VALUE ty_sval(
      ( tabname = 'SOOD' fieldname = 'OBJDES' fieldtext = 'Subject' ) ) ##NO_TEXT.

    CALL FUNCTION 'POPUP_GET_VALUES'
      EXPORTING
        popup_title     = 'Fill Subject'
        start_column    = '5'
        start_row       = '5'
      IMPORTING
        returncode      = lv_return
      TABLES
        fields          = lt_sval
      EXCEPTIONS
        error_in_fields = 1
        OTHERS          = 2
        ##FM_SUBRC_OK.
    IF sy-subrc <> 0 OR lv_return = 'A'.
      RETURN.
    ENDIF.

    DATA(lv_subject) = CONV so_obj_des(
      COND #( WHEN lt_sval IS NOT INITIAL THEN lt_sval[ 1 ]-value
              ELSE 'Template Transport' ) ) ##NO_TEXT.

    DATA(lt_text) = VALUE bbpt_tline( ).

    CALL FUNCTION 'READ_TEXT'
      EXPORTING
        client                  = sy-mandt
        id                      = 'ST'
        language                = sy-langu
        name                    = SWITCH thead-tdname( iv_target
                                    WHEN gc_target_ps4 THEN gc_text_ps4
                                    ELSE gc_text_qs4 )
        object                  = 'TEXT'
      TABLES
        lines                   = lt_text
      EXCEPTIONS
        id                      = 1
        language                = 2
        name                    = 3
        not_found               = 4
        object                  = 5
        reference_check         = 6
        wrong_access_to_archive = 7
        OTHERS                  = 8.
    IF sy-subrc <> 0.
      MESSAGE 'Email template text not found' TYPE fiehc_con_msgty_i
              DISPLAY LIKE fiehc_con_msgty_e ##NO_TEXT.
      RETURN.
    ENDIF.

    TRY.
        DATA(lo_bcs) = cl_bcs=>create_persistent( ).

        DATA(lt_body) = VALUE bcsy_text( FOR lw_text IN lt_text
                                         ( line = lw_text-tdline ) ).

        DATA(lo_document) = cl_document_bcs=>create_document(
                              i_type    = 'RAW'
                              i_subject = lv_subject
                              i_text    = lt_body ) ##NO_TEXT.

        lo_document->add_attachment(
          i_attachment_type    = 'xls'
          i_attachment_subject = |Template Email { iv_target }|
          i_attachment_size    = CONV #( xstrlen( iv_xstring ) )
          i_att_content_hex    = cl_bcs_convert=>xstring_to_solix( iv_xstring = iv_xstring )
          i_attachment_header  = VALUE #(
            ( line = |Template Request { iv_target }.xlsx| ) ) ) ##NO_TEXT.

        lo_bcs->set_document( i_document = lo_document ).

        lo_bcs->set_sender( i_sender = cl_cam_address_bcs=>create_internet_address(
                                         i_address_string = gc_sender_mail ) ).

        lo_bcs->add_recipient(
          i_recipient = cl_cam_address_bcs=>create_internet_address(
                          i_address_string = gc_recv_mail )
          i_express   = abap_true ).

        lo_bcs->set_message_subject( ip_subject = CONV #( lv_subject ) ).

        IF lo_bcs->send( ) = abap_true.
          COMMIT WORK.
        ENDIF.

      CATCH cx_address_bcs INTO DATA(lo_cx_address).
        MESSAGE lo_cx_address->get_text( ) TYPE fiehc_con_msgty_i
                DISPLAY LIKE fiehc_con_msgty_e.
      CATCH cx_document_bcs INTO DATA(lo_cx_document).
        MESSAGE lo_cx_document->get_text( ) TYPE fiehc_con_msgty_i
                DISPLAY LIKE fiehc_con_msgty_e.
      CATCH cx_send_req_bcs INTO DATA(lo_cx_send_req).
        MESSAGE lo_cx_send_req->get_text( ) TYPE fiehc_con_msgty_i
                DISPLAY LIKE fiehc_con_msgty_e.
      CATCH cx_bcs INTO DATA(lo_cx_bcs).
        MESSAGE lo_cx_bcs->get_text( ) TYPE fiehc_con_msgty_i
                DISPLAY LIKE fiehc_con_msgty_e.
    ENDTRY.
  ENDMETHOD.

  METHOD get_jira_lead.
    "TODO pindahkan ke ztca_mapping begitu entry-nya dimaintain
    rw_mention = VALUE #( id   = '712020:617a644e-ed82-4d9c-aa89-949a89251b93'
                          name = '@Budiman Ompusunggu' ) ##NO_TEXT.
  ENDMETHOD.

  METHOD get_jira_head.
    "TODO pindahkan ke ztca_mapping begitu entry-nya dimaintain
    rw_mention = VALUE #( id   = '712020:af0d3ed5-ab7a-44fd-8d6e-f5ade6dc86db'
                          name = '@Ramadhany Herlambang' ) ##NO_TEXT.
  ENDMETHOD.

  METHOD get_jira_basis.
    "TODO pindahkan ke ztca_mapping begitu entry-nya dimaintain
    rt_mention = VALUE #(
      ( id = '712020:ad73f308-4acd-4d8a-b754-19b12a342c07' name = '@Erwin Kusdyanta' )
      ( id = '712020:17b37255-50b4-4612-8a23-323e09add3f4' name = '@Aditya Saputra' )
      ( id = '712020:798dbc61-0785-49c4-8331-c6179fc01cad' name = '@Bambang Priatmoko' ) ) ##NO_TEXT.
  ENDMETHOD.

  METHOD jira_escape.
    rv_text = escape( val    = CONV string( iv_text )
                      format = cl_abap_format=>e_json_string ).
  ENDMETHOD.

  METHOD jira_text.
    DATA(lv_text) = jira_escape( iv_text ).

    IF iv_mailto = abap_true.
      rv_node = |\{ "type": "text", "text": "{ lv_text }", "marks": [ | &&
                |\{ "type": "link", "attrs": \{ "href": "mailto:{ lv_text }" \} \} ] \}|.
    ELSE.
      rv_node = |\{ "type": "text", "text": "{ lv_text }" \}|.
    ENDIF.
  ENDMETHOD.

  METHOD jira_mention_node.
    rv_node = |\{ "type": "mention", "attrs": \{ "id": "{ jira_escape( iw_mention-id ) }", | &&
              |"text": "{ jira_escape( iw_mention-name ) }", "accessLevel": "" \} \}|.
  ENDMETHOD.

  METHOD jira_paragraph.
    rv_node = |\{ "type": "paragraph", "content": [ | &&
              |{ concat_lines_of( table = it_nodes sep = `,` ) } ] \}|.
  ENDMETHOD.

  METHOD jira_cell.
    DATA(lt_node) = VALUE string_table(
      ( jira_text( iv_text = iv_text iv_mailto = iv_mailto ) ) ).

    rv_node = |\{ "type": "tableCell", "content": [ { jira_paragraph( lt_node ) } ] \}|.
  ENDMETHOD.

  METHOD jira_row.
    rv_node = |\{ "type": "tableRow", "content": [ | &&
              |{ concat_lines_of( table = it_cells sep = `,` ) } ] \}|.
  ENDMETHOD.

  METHOD build_jira_comment.
    CONSTANTS lc_hard_break TYPE string VALUE '{ "type": "hardBreak" }'.

    DATA: lt_content TYPE string_table,
          lt_row     TYPE string_table.

    APPEND jira_paragraph( VALUE #( ( jira_text( 'Dear All;' ) ) ) )
      TO lt_content ##NO_TEXT.

    APPEND jira_paragraph( VALUE #( ( jira_text( 'Kindly need your approval :' ) ) ) )
      TO lt_content ##NO_TEXT.

    APPEND jira_paragraph( VALUE #( ( jira_text( 'Abap Lead : ' ) )
                                    ( jira_mention_node( get_jira_lead( ) ) )
                                    ( jira_text( ` ` ) ) ) )
      TO lt_content ##NO_TEXT.

    IF iv_target = 'PS4'.
      APPEND jira_paragraph( VALUE #( ( jira_text( 'SAP Head : ' ) )
                                      ( jira_mention_node( get_jira_head( ) ) )
                                      ( jira_text( ` ` ) ) ) )
        TO lt_content ##NO_TEXT.
    ENDIF.

    APPEND jira_paragraph( VALUE #(
      ( jira_text( |for transporting following TR's to { iv_target } system| ) ) ) )
      TO lt_content ##NO_TEXT.

    "Baris header - kolom pertama sengaja kosong, mengikuti format approval.
    "Target PS4 memakai dua kolom tambahan Date dan Time, sama seperti
    "template Excel-nya; QS4 tidak memuat keduanya.
    DATA(lv_with_time) = xsdbool( iv_target = gc_target_ps4 ).

    DATA lt_cell TYPE string_table.

    APPEND jira_cell( ` ` ) TO lt_cell.
    APPEND jira_cell( 'Request/Task' ) TO lt_cell ##NO_TEXT.
    APPEND jira_cell( 'Short Description' ) TO lt_cell ##NO_TEXT.
    IF lv_with_time = abap_true.
      APPEND jira_cell( 'Date' ) TO lt_cell ##NO_TEXT.
      APPEND jira_cell( 'Time' ) TO lt_cell ##NO_TEXT.
    ENDIF.
    APPEND jira_cell( 'Team' ) TO lt_cell ##NO_TEXT.
    APPEND jira_cell( 'Last Changed By' ) TO lt_cell ##NO_TEXT.
    APPEND jira_cell( 'E-Mail Address' ) TO lt_cell ##NO_TEXT.
    APPEND jira_cell( 'Type' ) TO lt_cell ##NO_TEXT.
    APPEND jira_cell( 'Target System' ) TO lt_cell ##NO_TEXT.

    APPEND jira_row( lt_cell ) TO lt_row.

    "satu tableRow per TR yang dicentang
    LOOP AT it_rows INTO DATA(lw_row).
      CLEAR lt_cell.

      APPEND jira_cell( |{ lw_row-seq_no }| ) TO lt_cell.
      APPEND jira_cell( lw_row-trkorr ) TO lt_cell.
      APPEND jira_cell( lw_row-as4text ) TO lt_cell.
      IF lv_with_time = abap_true.
        APPEND jira_cell( |{ lw_row-date DATE = USER }| ) TO lt_cell.
        APPEND jira_cell( |{ lw_row-time }| ) TO lt_cell.
      ENDIF.
      APPEND jira_cell( lw_row-team ) TO lt_cell.
      APPEND jira_cell( lw_row-as4user ) TO lt_cell.
      APPEND jira_cell( iv_text = lw_row-email iv_mailto = abap_true ) TO lt_cell.
      APPEND jira_cell( lw_row-trfunction ) TO lt_cell.
      APPEND jira_cell( lw_row-target ) TO lt_cell.

      APPEND jira_row( lt_cell ) TO lt_row.
    ENDLOOP.

    APPEND |\{ "type": "table", "attrs": \{ "isNumberColumnEnabled": false, | &&
           |"layout": "center" \}, "content": [ | &&
           |{ concat_lines_of( table = lt_row sep = `,` ) } ] \}|
      TO lt_content.

    DATA(lt_close) = VALUE string_table(
      ( jira_text( |Dear basis kindly help transport TR below to { iv_target }.| ) )
      ( lc_hard_break ) ).

    DATA(lt_basis) = get_jira_basis( ).
    LOOP AT lt_basis INTO DATA(lw_basis).
      APPEND jira_mention_node( lw_basis ) TO lt_close.
      APPEND jira_text( ` ` ) TO lt_close.
    ENDLOOP.

    APPEND lc_hard_break TO lt_close.
    APPEND jira_text( 'Terima Kasih.' ) TO lt_close ##NO_TEXT.
    APPEND lc_hard_break TO lt_close.
    APPEND jira_text( 'Erico.' ) TO lt_close ##NO_TEXT.

    APPEND jira_paragraph( lt_close ) TO lt_content.

    rv_json = |\{ "body": \{ "type": "doc", "version": 1, "content": [ | &&
              |{ concat_lines_of( table = lt_content sep = `,` ) } ] \} \}|.
  ENDMETHOD.

  METHOD json_to_lines.
    "FM menyambung tdline dengan && yang membuang blank di ujung baris, jadi
    "potongan tidak boleh berakhir dengan spasi - kalau tidak, spasi di dalam
    "deskripsi TR bisa hilang dan JSON-nya rusak.
    CONSTANTS lc_width TYPE i VALUE 132.

    DATA(lv_rest) = iv_json.

    WHILE lv_rest IS NOT INITIAL.
      DATA(lv_len) = COND i( WHEN strlen( lv_rest ) > lc_width THEN lc_width
                             ELSE strlen( lv_rest ) ).

      WHILE lv_len > 1
        AND substring( val = lv_rest off = lv_len - 1 len = 1 ) = ` `.
        lv_len = lv_len - 1.
      ENDWHILE.

      APPEND VALUE #( tdline = substring( val = lv_rest off = 0 len = lv_len ) ) TO rt_lines.
      lv_rest = substring( val = lv_rest off = lv_len ).
    ENDWHILE.
  ENDMETHOD.

  METHOD post_jira_approval.
    IF it_rows IS INITIAL.
      MESSAGE 'Please Choose TR' TYPE fiehc_con_msgty_i
              DISPLAY LIKE fiehc_con_msgty_e ##NO_TEXT.
      RETURN.
    ENDIF.


    DATA(lt_content) = json_to_lines( build_jira_comment( iv_target = iv_target
                                                          it_rows   = it_rows ) ).

    IF gw_entry_time-delayed = abap_true.
      save_to_table(
          iv_target  = iv_target
          iw_entry   = gw_entry_time
          it_content = lt_content
      ).
    ELSE.

      CONSTANTS lc_http_created TYPE i VALUE 201.

      DATA: lv_status  TYPE i,
            lv_message TYPE string.

      CALL FUNCTION 'ZFI_CA_SEND_REQ_APPRV_JIR'
        EXPORTING
          iv_endpoint    = iv_endpoint
          iv_destiantion = iv_target
          it_content     = lt_content
        IMPORTING
          ev_status      = lv_status
          ev_message     = lv_message.

      "201 berarti komentar terbentuk; selain itu pesan dari Jira ditampilkan apa adanya
      IF lv_status = lc_http_created.
        MESSAGE lv_message TYPE fiehc_con_msgty_i.
      ELSE.
        MESSAGE lv_message TYPE fiehc_con_msgty_i DISPLAY LIKE fiehc_con_msgty_e.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD update_cacr.
    IF mt_trdata IS INITIAL.
      RETURN.
    ENDIF.

    LOOP AT mt_trdata INTO DATA(lw_trdata) WHERE strkorr  IS INITIAL
                                             AND checkbox = abap_true.
      DATA(lv_crnumber) = get_crnumber( lw_trdata ).

      DATA(lv_lastloc) = COND tarsystem( WHEN iv_lastloc IS NOT INITIAL THEN iv_lastloc
                                         ELSE lw_trdata-lastloc ).

      DATA(lv_status) = COND zde_crstatus( WHEN lv_lastloc = gc_target_ds4 THEN '2'
                                           WHEN lv_lastloc = gc_target_qs4 THEN '3'
                                           WHEN lv_lastloc = gc_target_ps4 THEN '4' ).

      DATA(lw_chg_req) = VALUE ztca_chgreq_stat( crnumber = lv_crnumber
                                                 status   = lv_status
                                                 chgdate  = sy-datum
                                                 chgtime  = sy-uzeit
                                                 chguser  = sy-uname ).

      UPDATE ztca_chgreq SET status = @lv_status WHERE crnumber = @lv_crnumber.
      IF sy-subrc = 0.
        INSERT ztca_chgreq_stat FROM lw_chg_req.
        IF sy-subrc = 0.
          COMMIT WORK.
        ELSE.
          ROLLBACK WORK.
        ENDIF.
      ELSE.
        ROLLBACK WORK.
      ENDIF.

      CLEAR: lw_chg_req, lv_crnumber, lv_status.
    ENDLOOP.
  ENDMETHOD.

  METHOD save_to_table.
    DATA(lv_name_text) = get_text_name( iv_target = iv_target
                                        iw_entry  = iw_entry ).

    save_text(
        iv_name    = lv_name_text
        it_content = it_content
    ).

    DATA(lw_apprv_jira) = VALUE ztca_apprv_jira(
        mandt     = sy-mandt
        endpoint  = iw_entry-endpoint
        timestamp = /accgo/cl_cmn_timecalc_utility=>get_utc( )
        target    = iv_target
        send      = abap_false
        name_text = lv_name_text
        approver  = iw_entry-approver
        username  = sy-uname
    ).

    INSERT ztca_apprv_jira FROM lw_apprv_jira.
    IF sy-subrc = 0.
      COMMIT WORK.
    ELSE.
      ROLLBACK WORK.
    ENDIF.
  ENDMETHOD.

  METHOD save_text.
    DATA(lw_head) = VALUE thead(
      tdobject = gc_object
      tdspras  = sy-langu
      tdid     = gc_id
      tdname   = iv_name
    ).

    CALL FUNCTION 'SAVE_TEXT'
      EXPORTING
        client          = sy-mandt
        header          = lw_head
        savemode_direct = abap_true
      TABLES
        lines           = it_content
      EXCEPTIONS
        id              = 1
        language        = 2
        name            = 3
        object          = 4
        OTHERS          = 5.
    IF sy-subrc <> 0.
* Implement suitable error handling here
    ELSE.
      MESSAGE 'Succsesfuly save' TYPE 'S'.
    ENDIF.
  ENDMETHOD.

  METHOD get_text_name.
    rv_name = gc_prefix_text.
    REPLACE '(CLIENT)' IN rv_name WITH iv_target.
    REPLACE '(ENDPOINT)' IN rv_name WITH iw_entry-endpoint.
  ENDMETHOD.

ENDCLASS.

CLASS lcl_singleton IMPLEMENTATION.

  METHOD create.
    IF go_main IS NOT BOUND.
      go_main = NEW lcl_main( ).
    ENDIF.
    go_main->initialize( ).
  ENDMETHOD.

  METHOD execute.
    IF go_main IS BOUND.
      go_main->execute_foroground( ).
    ENDIF.
  ENDMETHOD.

  METHOD pbo_template.
    IF go_main IS BOUND.
      go_main->pbo_template( ).
    ENDIF.
  ENDMETHOD.

  METHOD set_screen.
    IF go_main IS BOUND.
      go_main->set_screen( ).
    ENDIF.
  ENDMETHOD.

  METHOD pai_template.
    IF go_main IS BOUND.
      go_main->pai_template( ).
    ENDIF.
  ENDMETHOD.

  METHOD user_command.
    IF go_main IS BOUND.
      go_main->user_command( iv_ucomm ).
    ENDIF.
  ENDMETHOD.

  METHOD free_grid.
    IF go_main IS BOUND.
      go_main->free_grid( ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------
* EVENT BLOCK
*----------------------------------------------------------------------
INITIALIZATION.
  lcl_singleton=>create( ).

AT SELECTION-SCREEN OUTPUT.
  "grid di default screen dari run sebelumnya jangan ikut tampil di sini
  lcl_singleton=>free_grid( ).

START-OF-SELECTION.
  lcl_singleton=>execute( ).

AT USER-COMMAND.
  lcl_singleton=>user_command( sy-ucomm ).

*----------------------------------------------------------------------
* DYNPRO 1010 - Template entry (Export / Email)
*----------------------------------------------------------------------
MODULE status_1010 OUTPUT.
  lcl_singleton=>pbo_template( ).
ENDMODULE.

MODULE user_command_1010 INPUT.
  lcl_singleton=>pai_template( ).
ENDMODULE.
*&---------------------------------------------------------------------*
*& Module SET_SCREEN OUTPUT
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
MODULE set_screen OUTPUT.
  lcl_singleton=>set_screen( ).
ENDMODULE.
